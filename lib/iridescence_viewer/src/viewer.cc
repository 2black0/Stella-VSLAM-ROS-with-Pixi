#include "iridescence_viewer/viewer.h"

#include "stella_vslam/config.h"
#include "stella_vslam/data/keyframe.h"
#include "stella_vslam/data/landmark.h"
#include "stella_vslam/publish/frame_publisher.h"
#include "stella_vslam/publish/map_publisher.h"
#include "stella_vslam/util/yaml.h"

#include <glk/primitives/primitives.hpp>
#include <glk/pointcloud_buffer.hpp>
#include <glk/splatting.hpp>
#include <glk/texture_opencv.hpp>
#include <glk/thin_lines.hpp>
#include <guik/viewer/light_viewer.hpp>

#include <chrono>
#include <thread>

namespace {
Eigen::Matrix4d rotate_pose(Eigen::Matrix4d pose_cw, Eigen::Matrix3d rot) {
    return (rot * Eigen::Affine3d(Eigen::Translation3d(pose_cw.block<3, 1>(0, 3)) * pose_cw.block<3, 3>(0, 0))).matrix();
}
} // namespace

namespace iridescence_viewer {

viewer::viewer(const YAML::Node& yaml_node,
               const std::shared_ptr<stella_vslam::publish::frame_publisher>& frame_publisher,
               const std::shared_ptr<stella_vslam::publish::map_publisher>& map_publisher)
    : frame_publisher_(frame_publisher), map_publisher_(map_publisher),
      interval_ms_(1000.0f / yaml_node["fps"].as<float>(30.0)),
      select_keypoint_by_id_(false),
      keypoint_id_(0),
      select_landmark_by_id_(false),
      landmark_id_(0),
      is_paused_(false),
      show_all_keypoints_(false),
      show_rect_(false),
      show_covisibility_graph_(true),
      min_shared_lms_(100),
      show_spanning_tree_(true),
      show_loop_edge_(true),
      follow_camera_(false),
      filter_by_octave_(false),
      octave_(0),
      point_splatting_(true),
      current_frame_scale_(0.05f),
      keyframe_scale_(0.05f),
      selected_landmark_scale_(0.01f),
      texture_(nullptr),
      clicked_(false) {
    rot_ros_to_cv_map_frame_ << 0, 0, 1,
        -1, 0, 0,
        0, -1, 0;
}

void viewer::ui_callback(guik::LightViewer* viewer) {
    clicked_point3d_ = viewer->pick_point(ImGuiMouseButton_Left);

    ImGui::Begin("info", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    const auto state = frame_publisher_->get_tracking_state();
    ImGui::Text("state: %s", state.c_str());
    const auto tracking_time_elapsed_ms = frame_publisher_->get_tracking_time_elapsed_ms();
    ImGui::Text("tracking time [ms]: %f", tracking_time_elapsed_ms);
    const auto extraction_time_elapsed_ms = frame_publisher_->get_extraction_time_elapsed_ms();
    ImGui::Text("extraction time [ms]: %f", extraction_time_elapsed_ms);
    ImGui::Text("Selected keypoint ID: %d", keypoint_id_);
    ImGui::Text("Selected landmark ID: %d", landmark_id_);

    ImGui::Begin("Selected keypoint info", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    if (!keypoint_info_.empty()) {
        ImGui::Text("ID: %d", keypoint_id_);
        ImGui::Text("%s", keypoint_info_.c_str());
    }

    ImGui::Begin("Selected landmark info", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    if (!landmark_info_.empty()) {
        ImGui::Text("ID: %d", landmark_id_);
        ImGui::Text("%s", landmark_info_.c_str());
    }

    ImGui::Begin("image", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    if (texture_) {
        ImVec2 screen_pos = ImGui::GetCursorScreenPos();
        Eigen::Vector2i size = (texture_->size().cast<double>()).cast<int>();
        ImGui::Image(reinterpret_cast<void*>(texture_->id()), ImVec2(size[0], size[1]), ImVec2(0, 0), ImVec2(1, 1));
        ImVec2 mouse_pos = ImGui::GetIO().MousePos;
        if (ImGui::IsItemHovered() && ImGui::IsMouseClicked(0)) {
            clicked_ = true;
            clicked_pt_ = (Eigen::Vector2d() << mouse_pos.x - screen_pos.x, mouse_pos.y - screen_pos.y).finished();
        }
    }

    ImGui::Begin("ui", nullptr, ImGuiWindowFlags_AlwaysAutoResize);
    ImGui::Checkbox("Select keypoint by ID", &select_keypoint_by_id_);
    if (select_keypoint_by_id_) {
        ImGui::InputInt("Keypoint ID", &keypoint_id_);
        if (0 > keypoint_id_) {
            keypoint_id_ = 0;
        }
        select_landmark_by_id_ = false;
    }
    ImGui::Checkbox("Select landmark by ID", &select_landmark_by_id_);
    if (select_landmark_by_id_) {
        ImGui::InputInt("Landmark ID", &landmark_id_);
        if (0 > landmark_id_) {
            landmark_id_ = 0;
        }
        select_keypoint_by_id_ = false;
    }
    ImGui::DragFloat("CurrentFrame scale", &current_frame_scale_, 0.01f, 0.01f, 1.0f);
    ImGui::DragFloat("Keyframe scale", &keyframe_scale_, 0.01f, 0.01f, 1.0f);
    ImGui::DragFloat("Selected landmark scale", &selected_landmark_scale_, 0.01f, 0.01f, 1.0f);
    ImGui::Checkbox("Show all keypoints", &show_all_keypoints_);
    ImGui::Checkbox("Show rect", &show_rect_);
    ImGui::Checkbox("Show covisibility graph", &show_covisibility_graph_);
    if (show_covisibility_graph_) {
        ImGui::DragInt("minimum shared landmarks", &min_shared_lms_);
    }
    ImGui::Checkbox("Show spanning tree", &show_spanning_tree_);
    ImGui::Checkbox("Show loop edge", &show_loop_edge_);
    ImGui::Checkbox("Follow camera", &follow_camera_);
    const char* items[] = {"orbit", "orbit_xz", "topdown", "arcball", "fps"};
    static int item_current_idx = 0;
    const char* combo_preview_value = items[item_current_idx];
    if (ImGui::BeginCombo("camera mode", combo_preview_value)) {
        for (int n = 0; n < IM_ARRAYSIZE(items); n++) {
            const bool is_selected = (item_current_idx == n);
            if (ImGui::Selectable(items[n], is_selected)) {
                item_current_idx = n;
                if (n == 0) {
                    viewer->use_orbit_camera_control();
                }
                if (n == 1) {
                    viewer->use_orbit_camera_control_xz();
                }
                if (n == 2) {
                    viewer->use_topdown_camera_control();
                }
                if (n == 3) {
                    viewer->use_arcball_camera_control();
                }
                if (n == 4) {
                    viewer->use_fps_camera_control();
                }
            }
            if (is_selected) {
                ImGui::SetItemDefaultFocus();
            }
        }
        ImGui::EndCombo();
    }
    ImGui::Checkbox("Filter by octave", &filter_by_octave_);
    if (filter_by_octave_) {
        ImGui::InputInt("Octave", &octave_);
    }
    ImGui::Checkbox("Point splatting", &point_splatting_);
    if (point_splatting_) {
        ImGui::DragFloat("Point radius", &point_radius_, 0.001f, 0.001f, 1.0f);
    }
    for (auto&& pair : checkbox_callback_map_) {
        if (ImGui::Checkbox(pair.first.c_str(), &is_paused_)) {
            if (pair.second) {
                pair.second(is_paused_);
            }
        }
    }
    for (auto&& pair : button_callback_map_) {
        if (ImGui::Button(pair.first.c_str())) {
            if (pair.second) {
                pair.second();
            }
        }
    }
}

void viewer::run() {
    auto viewer = guik::LightViewer::instance(Eigen::Vector2i(-1, -1), false, "iridescence_viewer");

    viewer->register_ui_callback("ui", [this, &viewer] { ui_callback(viewer); });

    while (viewer->spin_once()) {
        viewer->clear_drawables();

        std::vector<std::shared_ptr<stella_vslam::data::keyframe>> keyfrms;
        map_publisher_->get_keyframes(keyfrms);

        std::vector<std::shared_ptr<stella_vslam::data::landmark>> landmarks;
        std::set<std::shared_ptr<stella_vslam::data::landmark>> local_landmarks;
        map_publisher_->get_landmarks(landmarks, local_landmarks);

        Eigen::Matrix4d current_frame_pose = rotate_pose(map_publisher_->get_current_cam_pose().inverse().eval(), rot_ros_to_cv_map_frame_);
        viewer->update_drawable("current_frame", glk::Primitives::wire_frustum(), guik::FlatColor(Eigen::Vector4f(0.7f, 0.7f, 1.0f, 1.0f), current_frame_pose).scale(current_frame_scale_));
        if (follow_camera_) {
            viewer->lookat(current_frame_pose.block<3, 1>(0, 3).cast<float>());
        }

        for (const auto& keyfrm : keyfrms) {
            if (!keyfrm || keyfrm->will_be_erased()) {
                continue;
            }
            Eigen::Matrix4d keyfrms_pose = rotate_pose(keyfrm->get_pose_wc(), rot_ros_to_cv_map_frame_);
            const auto name = std::string("keyfrms_pose_") + std::to_string(keyfrm->id_);
            viewer->update_drawable(name, glk::Primitives::wire_frustum(), guik::FlatColor(Eigen::Vector4f(0.0f, 1.0f, 0.0f, 1.0f), keyfrms_pose).scale(keyframe_scale_));
        }

        // draw covisibility graph
        if (show_covisibility_graph_) {
            draw_covisibility_graph(viewer, keyfrms);
        }

        if (show_spanning_tree_) {
            draw_spanning_tree(viewer, keyfrms);
        }

        if (show_loop_edge_) {
            draw_loop_edge(viewer, keyfrms);
        }

        std::vector<Eigen::Vector3f> points;
        std::vector<Eigen::Vector3f> normals;
        float min_distance = std::numeric_limits<float>::max();
        unsigned int min_distance_id = 0;
        for (const auto& lm : landmarks) {
            if (!lm || lm->will_be_erased()) {
                continue;
            }
            const Eigen::Vector3d pos_w = rot_ros_to_cv_map_frame_ * lm->get_pos_in_world();
            if (select_landmark_by_id_ && landmark_id_ == lm->id_) {
                viewer->update_drawable("selected point", glk::Primitives::sphere(), guik::FlatColor(Eigen::Vector4f(1.0f, 0.0f, 0.0f, 1.0f)).translate(pos_w).scale(selected_landmark_scale_));
                landmark_info_ = "num_observed: " + std::to_string(lm->get_num_observed()) + "\nobserved_ratio: " + std::to_string(lm->get_observed_ratio());
            }
            if (clicked_point3d_) {
                float distance = (pos_w.cast<float>() - *clicked_point3d_).norm();
                if (distance < min_distance) {
                    min_distance = distance;
                    min_distance_id = lm->id_;
                }
            }
            points.push_back(pos_w.cast<float>());
            if (point_splatting_) {
                normals.push_back((rot_ros_to_cv_map_frame_ * lm->get_obs_mean_normal()).cast<float>());
            }
        }
        if (clicked_point3d_) {
            if (min_distance < std::numeric_limits<float>::max()) {
                select_landmark_by_id_ = true;
                landmark_id_ = min_distance_id;
            }
        }
        auto cloud_buffer = std::make_shared<glk::PointCloudBuffer>(points);

        if (point_splatting_) {
            cloud_buffer->add_normals(normals);

            // Create a splatting shader
            auto splatting_shader = glk::create_splatting_shader();
            // Create a splatting instance
            auto splatting = std::make_shared<glk::Splatting>(splatting_shader);
            splatting->set_point_radius(point_radius_);
            splatting->set_cloud_buffer(cloud_buffer);

            viewer->update_drawable("map", splatting, guik::FlatColor(Eigen::Vector4f(1.0f, 0.5f, 0.0f, 1.0f)));
        }
        else {
            viewer->update_drawable("map", cloud_buffer, guik::FlatColor(Eigen::Vector4f(1.0f, 0.5f, 0.0f, 1.0f)));
        }

        viewer->set_draw_xy_grid(false);
        viewer->update_drawable("coordinate_system", glk::Primitives::coordinate_system(), guik::VertexColor());

        // Update texture
        cv::Mat img = frame_publisher_->get_image();
        if (img.channels() == 1) {
            cvtColor(img, img, cv::COLOR_GRAY2BGR);
        }
        auto keypoints_and_landmarks = frame_publisher_->get_keypoints_and_landmarks();
        auto keypoints = keypoints_and_landmarks.first;
        auto frame_landmarks = keypoints_and_landmarks.second;
        draw_tracked_points(img, keypoints, frame_landmarks, frame_publisher_->get_mapping_is_enabled());
        texture_ = glk::create_texture(img);

        if (select_keypoint_by_id_ && keypoint_id_ < frame_landmarks.size()) {
            auto lm = frame_landmarks.at(keypoint_id_);
            if (!lm || lm->will_be_erased()) {
                continue;
            }
            landmark_id_ = lm->id_;
            const Eigen::Vector3d pos_w = rot_ros_to_cv_map_frame_ * lm->get_pos_in_world();
            viewer->update_drawable("selected point", glk::Primitives::sphere(), guik::FlatColor(Eigen::Vector4f(1.0f, 0.0f, 0.0f, 1.0f)).translate(pos_w).scale(selected_landmark_scale_));
            landmark_info_ = "num_observed: " + std::to_string(lm->get_num_observed()) + "\nobserved_ratio: " + std::to_string(lm->get_observed_ratio());
        }

        if (terminate_is_requested()) {
            break;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(interval_ms_));
    }

    if (close_callback_) {
        close_callback_();
    }
}

void viewer::draw_rect(cv::Mat& img, const cv::KeyPoint& keypoint, const cv::Scalar& color) {
    float angle_rad = keypoint.angle / 180.0 * M_PI;
    float width = keypoint.size;
    float half_width = width / 2;
    cv::Point2f pt = keypoint.pt;
    cv::Point2f pt2 = pt + cv::Point2f(half_width * std::cos(angle_rad), half_width * std::sin(angle_rad));
    cv::line(img, pt, pt2, color, 1);
    cv::RotatedRect rotatedRectangle(pt, cv::Size(width, width), keypoint.angle);
    cv::Point2f vertices[4];
    rotatedRectangle.points(vertices);
    for (int i = 0; i < 4; ++i) {
        line(img, vertices[i], vertices[(i + 1) % 4], color, 1);
    }
}

unsigned int viewer::draw_tracked_points(
    cv::Mat& img,
    const std::vector<cv::KeyPoint>& keypoints,
    const std::vector<std::shared_ptr<stella_vslam::data::landmark>>& landmarks,
    const bool mapping_is_enabled) {
    unsigned int num_tracked = 0;

    if (show_all_keypoints_) {
        for (unsigned int i = 0; i < keypoints.size(); ++i) {
            if (filter_by_octave_ && octave_ != keypoints.at(i).octave) {
                continue;
            }

            const cv::Scalar color{0, 255, 255};
            cv::circle(img, keypoints.at(i).pt, 2, color, -1);
            if (show_rect_) {
                draw_rect(img, keypoints.at(i), color);
            }
        }
    }
    constexpr int mark_size = 10;
    const cv::Scalar mark_color{0, 0, 255};
    std::vector<std::pair<double, unsigned int>> distance_and_keypoint_idx;
    bool keypoint_exists = false;
    for (unsigned int i = 0; i < keypoints.size(); ++i) {
        const auto& lm = landmarks.at(i);
        if (!lm) {
            continue;
        }
        if (lm->will_be_erased()) {
            continue;
        }
        if (filter_by_octave_ && octave_ != keypoints.at(i).octave) {
            continue;
        }

        if (clicked_) {
            distance_and_keypoint_idx.emplace_back(std::hypot(clicked_pt_(0) - keypoints.at(i).pt.x, clicked_pt_(1) - keypoints.at(i).pt.y), i);
        }
        const cv::Scalar keypoint_color{0, 255, 0};
        cv::circle(img, keypoints.at(i).pt, 2, keypoint_color, -1);
        if (show_rect_) {
            draw_rect(img, keypoints.at(i), keypoint_color);
        }
        if (select_landmark_by_id_ && lm->id_ == landmark_id_) {
            // Mark keypoint corresponding to the selected landmarks.
            cv::circle(img, keypoints.at(i).pt, mark_size, mark_color, 1);
            keypoint_exists = true;

            keypoint_info_ = "angle: " + std::to_string(keypoints.at(i).angle) + "\noctave: " + std::to_string(keypoints.at(i).octave);
        }

        ++num_tracked;
    }
    if (!keypoint_exists) {
        keypoint_info_ = "";
    }
    if (!distance_and_keypoint_idx.empty()) {
        auto min_distance_keypoint_idx = std::min_element(distance_and_keypoint_idx.begin(), distance_and_keypoint_idx.end());
        select_keypoint_by_id_ = true;
        keypoint_id_ = min_distance_keypoint_idx->second;
        clicked_ = false;
    }
    if (select_keypoint_by_id_ && keypoint_id_ < keypoints.size()) {
        // Mark selected keypoint
        cv::circle(img, keypoints.at(keypoint_id_).pt, mark_size, mark_color, 1);

        keypoint_info_ = "angle: " + std::to_string(keypoints.at(keypoint_id_).angle) + "\noctave: " + std::to_string(keypoints.at(keypoint_id_).octave);
    }

    return num_tracked;
}

void viewer::draw_covisibility_graph(
    guik::LightViewer* viewer,
    std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms) {
    std::vector<Eigen::Vector3f> covisibility_graph_lines;
    for (const auto& keyfrm : keyfrms) {
        if (!keyfrm || keyfrm->will_be_erased()) {
            continue;
        }
        const stella_vslam::Vec3_t cam_center_1 = rot_ros_to_cv_map_frame_ * keyfrm->get_trans_wc();
        const auto covisibilities = keyfrm->graph_node_->get_covisibilities_over_min_num_shared_lms(min_shared_lms_);
        if (!covisibilities.empty()) {
            for (const auto& covisibility : covisibilities) {
                if (!covisibility || covisibility->will_be_erased()) {
                    continue;
                }
                if (covisibility->id_ < keyfrm->id_) {
                    continue;
                }
                const stella_vslam::Vec3_t cam_center_2 = rot_ros_to_cv_map_frame_ * covisibility->get_trans_wc();
                covisibility_graph_lines.push_back(cam_center_1.cast<float>());
                covisibility_graph_lines.push_back(cam_center_2.cast<float>());
            }
        }
    }
    auto covisibility_graph_drawable = std::make_shared<glk::ThinLines>(covisibility_graph_lines, false);
    viewer->update_drawable("covisibility graph", covisibility_graph_drawable, guik::FlatColor(Eigen::Vector4f(0.7f, 0.7f, 1.0f, 1.0f)));
}

void viewer::draw_spanning_tree(
    guik::LightViewer* viewer,
    std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms) {
    std::vector<Eigen::Vector3f> spanning_tree_lines;
    for (const auto& keyfrm : keyfrms) {
        if (!keyfrm || keyfrm->will_be_erased()) {
            continue;
        }
        auto spanning_parent = keyfrm->graph_node_->get_spanning_parent();
        if (spanning_parent) {
            const stella_vslam::Vec3_t cam_center_1 = rot_ros_to_cv_map_frame_ * keyfrm->get_trans_wc();
            const stella_vslam::Vec3_t cam_center_2 = rot_ros_to_cv_map_frame_ * spanning_parent->get_trans_wc();
            spanning_tree_lines.push_back(cam_center_1.cast<float>());
            spanning_tree_lines.push_back(cam_center_2.cast<float>());
        }
    }
    auto spanning_tree_drawable = std::make_shared<glk::ThinLines>(spanning_tree_lines, false);
    viewer->update_drawable("spanning tree", spanning_tree_drawable, guik::FlatColor(Eigen::Vector4f(1.0f, 0.0f, 0.0f, 1.0f)));
}

void viewer::draw_loop_edge(
    guik::LightViewer* viewer,
    std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms) {
    std::vector<Eigen::Vector3f> loop_edge_lines;
    for (const auto& keyfrm : keyfrms) {
        if (!keyfrm || keyfrm->will_be_erased()) {
            continue;
        }
        const stella_vslam::Vec3_t cam_center_1 = rot_ros_to_cv_map_frame_ * keyfrm->get_trans_wc();
        const auto loop_edges = keyfrm->graph_node_->get_loop_edges();
        for (const auto& loop_edge : loop_edges) {
            if (!loop_edge) {
                continue;
            }
            if (loop_edge->id_ < keyfrm->id_) {
                continue;
            }
            const stella_vslam::Vec3_t cam_center_2 = rot_ros_to_cv_map_frame_ * loop_edge->get_trans_wc();
            loop_edge_lines.push_back(cam_center_1.cast<float>());
            loop_edge_lines.push_back(cam_center_2.cast<float>());
        }
    }
    auto loop_edge_drawable = std::make_shared<glk::ThinLines>(loop_edge_lines, false);
    viewer->update_drawable("loop edge", loop_edge_drawable, guik::FlatColor(Eigen::Vector4f(1.0f, 0.0f, 0.0f, 1.0f)));
}

void viewer::request_terminate() {
    std::lock_guard<std::mutex> lock(mtx_terminate_);
    terminate_is_requested_ = true;
}

bool viewer::terminate_is_requested() {
    std::lock_guard<std::mutex> lock(mtx_terminate_);
    return terminate_is_requested_;
}

} // namespace iridescence_viewer
