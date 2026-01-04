#ifndef IRIDESCENCE_VIEWER_VIEWER_H
#define IRIDESCENCE_VIEWER_VIEWER_H

#include "stella_vslam/type.h"
#include "stella_vslam/util/yaml.h"

#include <memory>
#include <mutex>
#include <optional>

namespace stella_vslam {

class config;
namespace data {
class keyframe;
class landmark;
} // namespace data

namespace publish {
class frame_publisher;
class map_publisher;
} // namespace publish

} // namespace stella_vslam

namespace glk {
class Texture;
} // namespace glk

namespace guik {
class LightViewer;
} // namespace guik

namespace iridescence_viewer {

class viewer {
public:
    EIGEN_MAKE_ALIGNED_OPERATOR_NEW

    /**
     * Constructor
     * @param yaml_node
     * @param frame_publisher
     * @param map_publisher
     */
    viewer(const YAML::Node& yaml_node,
           const std::shared_ptr<stella_vslam::publish::frame_publisher>& frame_publisher,
           const std::shared_ptr<stella_vslam::publish::map_publisher>& map_publisher);

    /**
     * Main loop for window refresh
     */
    void run();

    /**
     * Request to terminate the viewer
     * (NOTE: this function does not wait for terminate)
     */
    void request_terminate();

    void add_checkbox(std::string name, std::function<void(bool)> callback) {
        checkbox_callback_map_.emplace_back(name, callback);
    }

    void add_button(std::string name, std::function<void()> callback) {
        button_callback_map_.emplace_back(name, callback);
    }

    void add_close_callback(std::function<void()> callback) {
        close_callback_ = callback;
    }

private:
    void ui_callback(guik::LightViewer* viewer);

    void draw_rect(cv::Mat& img, const cv::KeyPoint& keypoint, const cv::Scalar& color);
    unsigned int draw_tracked_points(
        cv::Mat& img,
        const std::vector<cv::KeyPoint>& keypoints,
        const std::vector<std::shared_ptr<stella_vslam::data::landmark>>& landmarks,
        const bool mapping_is_enabled);
    void draw_covisibility_graph(
        guik::LightViewer* viewer,
        std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms);
    void draw_spanning_tree(
        guik::LightViewer* viewer,
        std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms);
    void draw_loop_edge(
        guik::LightViewer* viewer,
        std::vector<std::shared_ptr<stella_vslam::data::keyframe>>& keyfrms);

    //! frame publisher
    const std::shared_ptr<stella_vslam::publish::frame_publisher> frame_publisher_;
    //! map publisher
    const std::shared_ptr<stella_vslam::publish::map_publisher> map_publisher_;

    std::vector<std::pair<std::string, std::function<void(bool)>>> checkbox_callback_map_;
    std::vector<std::pair<std::string, std::function<void()>>> button_callback_map_;
    std::function<void()> close_callback_ = nullptr;

    const unsigned int interval_ms_;

    bool select_keypoint_by_id_ = false;
    int keypoint_id_ = 0;
    bool select_landmark_by_id_ = false;
    int landmark_id_ = 0;
    bool is_paused_ = false;
    bool show_all_keypoints_ = false;
    bool show_rect_ = false;
    bool show_covisibility_graph_ = true;
    int min_shared_lms_ = 100;
    bool show_spanning_tree_ = false;
    bool show_loop_edge_ = false;
    bool follow_camera_ = true;
    bool filter_by_octave_ = false;
    int octave_ = 0;
    bool point_splatting_ = true;
    float point_radius_ = 0.01;
    float current_frame_scale_ = 0.05f;
    float keyframe_scale_ = 0.05f;
    float selected_landmark_scale_ = 0.01f;
    std::shared_ptr<glk::Texture> texture_ = nullptr;
    bool clicked_ = false;
    Eigen::Vector2d clicked_pt_;
    std::optional<Eigen::Vector3f> clicked_point3d_;
    std::string keypoint_info_;
    std::string landmark_info_;

    Eigen::Matrix3d rot_ros_to_cv_map_frame_;

    //-----------------------------------------
    // management for terminate process

    //! mutex for access to terminate procedure
    mutable std::mutex mtx_terminate_;

    /**
     * Check if termination is requested or not
     * @return
     */
    bool terminate_is_requested();

    //! flag which indicates termination is requested or not
    bool terminate_is_requested_ = false;
    //! flag which indicates whether the main loop is terminated or not
    bool is_terminated_ = true;
};

} // namespace iridescence_viewer

#endif // IRIDESCENCE_VIEWER_VIEWER_H
