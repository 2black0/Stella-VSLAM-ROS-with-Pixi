#ifdef HAVE_PANGOLIN_VIEWER
#include "pangolin_viewer/viewer.h"
#endif
#ifdef HAVE_IRIDESCENCE_VIEWER
#include "iridescence_viewer/viewer.h"
#endif
#ifdef HAVE_SOCKET_PUBLISHER
#include "socket_publisher/publisher.h"
#endif

#include "vehicles/multirotor/api/MultirotorRpcLibClient.hpp"

#include "stella_vslam/system.h"
#include "stella_vslam/config.h"
#include "stella_vslam/camera/base.h"
#include "stella_vslam/util/yaml.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cctype>
#include <cstdint>
#include <iostream>
#include <mutex>
#include <numeric>
#include <optional>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>
#include <utility>

#include <opencv2/core/mat.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/imgproc.hpp>
#include <spdlog/spdlog.h>
#include <popl.hpp>

#include <ghc/filesystem.hpp>
namespace fs = ghc::filesystem;

#ifdef USE_STACK_TRACE_LOGGER
#include <backward.hpp>
#endif

#ifdef USE_GOOGLE_PERFTOOLS
#include <gperftools/profiler.h>
#endif

namespace {

using ImageType = msr::airlib::ImageCaptureBase::ImageType;
using ImageRequest = msr::airlib::ImageCaptureBase::ImageRequest;
using ImageResponse = msr::airlib::ImageCaptureBase::ImageResponse;

struct airsim_source_options {
    std::string rpc_address = "127.0.0.1";
    std::uint16_t rpc_port = 41451;
    std::string vehicle_name = "Copter";
    std::string camera_name = "Camera";
    ImageType image_type = ImageType::Scene;
    bool pixels_as_float = false;
    bool compress = false;
};

std::string to_lower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

std::optional<ImageType> parse_image_type(const std::string& arg) {
    const std::string lower = to_lower(arg);
    if (lower == "scene") {
        return ImageType::Scene;
    }
    if (lower == "depth" || lower == "depthperspective") {
        return ImageType::DepthPerspective;
    }
    if (lower == "depthplanar") {
        return ImageType::DepthPlanar;
    }
    if (lower == "segmentation" || lower == "mask") {
        return ImageType::Segmentation;
    }
    if (lower == "infrared") {
        return ImageType::Infrared;
    }
    if (lower == "disparity") {
        return ImageType::DisparityNormalized;
    }
    return std::nullopt;
}

cv::Mat convert_response_to_bgr(const ImageResponse& response) {
    if (response.pixels_as_float) {
        const float* ptr = response.image_data_float.data();
        cv::Mat depth(response.height, response.width, CV_32FC1, const_cast<float*>(ptr));
        cv::Mat normalized;
        double min_val = 0.0;
        double max_val = 0.0;
        cv::minMaxLoc(depth, &min_val, &max_val);
        const double scale = (max_val - min_val) > 1e-6 ? 255.0 / (max_val - min_val) : 50.0;
        depth.convertTo(normalized, CV_8UC1, scale, -min_val * scale);
        cv::Mat colored;
        cv::applyColorMap(normalized, colored, cv::COLORMAP_VIRIDIS);
        return colored;
    }

    if (response.compress) {
        cv::Mat buffer(1, static_cast<int>(response.image_data_uint8.size()), CV_8UC1,
                       const_cast<uint8_t*>(response.image_data_uint8.data()));
        return cv::imdecode(buffer, cv::IMREAD_COLOR);
    }

    cv::Mat image(response.height, response.width, CV_8UC3,
                  const_cast<uint8_t*>(response.image_data_uint8.data()));
    return image.clone();
}

bool try_fetch_frame(msr::airlib::MultirotorRpcLibClient& client,
                     const ImageRequest& request,
                     const std::string& vehicle_name,
                     cv::Mat& frame) {
    const auto responses = client.simGetImages({request}, vehicle_name);
    if (responses.empty()) {
        return false;
    }

    const auto& response = responses.front();
    if (response.height <= 0 || response.width <= 0) {
        return false;
    }

    cv::Mat image = convert_response_to_bgr(response);
    if (image.empty()) {
        return false;
    }

    frame = std::move(image);
    return true;
}

} // namespace

int mono_tracking(const std::shared_ptr<stella_vslam::system>& slam,
                  const std::shared_ptr<stella_vslam::config>& cfg,
                  const airsim_source_options& source_opts,
                  const std::string& mask_img_path,
                  const float scale,
                  const std::string& map_db_path,
                  const std::string& viewer_string) {
    const cv::Mat mask = mask_img_path.empty() ? cv::Mat{} : cv::imread(mask_img_path, cv::IMREAD_GRAYSCALE);

#ifdef HAVE_PANGOLIN_VIEWER
    std::shared_ptr<pangolin_viewer::viewer> viewer;
    if (viewer_string == "pangolin_viewer") {
        viewer = std::make_shared<pangolin_viewer::viewer>(
            stella_vslam::util::yaml_optional_ref(cfg->yaml_node_, "PangolinViewer"),
            slam,
            slam->get_frame_publisher(),
            slam->get_map_publisher());
    }
#endif
#ifdef HAVE_IRIDESCENCE_VIEWER
    std::shared_ptr<iridescence_viewer::viewer> iridescence_viewer;
    std::mutex mtx_pause;
    bool is_paused = false;
    std::mutex mtx_terminate;
    bool terminate_is_requested = false;
    std::mutex mtx_step;
    unsigned int step_count = 0;
    if (viewer_string == "iridescence_viewer") {
        iridescence_viewer = std::make_shared<iridescence_viewer::viewer>(
            stella_vslam::util::yaml_optional_ref(cfg->yaml_node_, "IridescenceViewer"),
            slam->get_frame_publisher(),
            slam->get_map_publisher());
        iridescence_viewer->add_checkbox("Pause", [&is_paused, &mtx_pause](bool check) {
            std::lock_guard<std::mutex> lock(mtx_pause);
            is_paused = check;
        });
        iridescence_viewer->add_button("Step", [&step_count, &mtx_step] {
            std::lock_guard<std::mutex> lock(mtx_step);
            step_count++;
        });
        iridescence_viewer->add_button("Reset", [&slam] {
            slam->request_reset();
        });
        iridescence_viewer->add_button("Save and exit", [&is_paused, &mtx_pause, &terminate_is_requested, &mtx_terminate, &slam, &iridescence_viewer] {
            std::lock_guard<std::mutex> lock1(mtx_pause);
            is_paused = false;
            std::lock_guard<std::mutex> lock2(mtx_terminate);
            terminate_is_requested = true;
            iridescence_viewer->request_terminate();
        });
        iridescence_viewer->add_close_callback([&is_paused, &mtx_pause, &terminate_is_requested, &mtx_terminate] {
            std::lock_guard<std::mutex> lock1(mtx_pause);
            is_paused = false;
            std::lock_guard<std::mutex> lock2(mtx_terminate);
            terminate_is_requested = true;
        });
    }
#endif
#ifdef HAVE_SOCKET_PUBLISHER
    std::shared_ptr<socket_publisher::publisher> publisher;
    if (viewer_string == "socket_publisher") {
        publisher = std::make_shared<socket_publisher::publisher>(
            stella_vslam::util::yaml_optional_ref(cfg->yaml_node_, "SocketPublisher"),
            slam,
            slam->get_frame_publisher(),
            slam->get_map_publisher());
    }
#endif

    msr::airlib::MultirotorRpcLibClient client(source_opts.rpc_address, source_opts.rpc_port);
    spdlog::info("Connecting to AirSim at {}:{} (vehicle='{}', camera='{}')",
                 source_opts.rpc_address,
                 source_opts.rpc_port,
                 source_opts.vehicle_name,
                 source_opts.camera_name);
    try {
        client.confirmConnection();
        client.enableApiControl(false, source_opts.vehicle_name);
    }
    catch (const std::exception& e) {
        spdlog::critical("Failed to connect to AirSim: {}", e.what());
        slam->shutdown();
        return EXIT_FAILURE;
    }

    const ImageRequest request(source_opts.camera_name,
                               source_opts.image_type,
                               source_opts.pixels_as_float,
                               source_opts.compress);

    std::vector<double> track_times;
    std::atomic<bool> keep_running{true};

    std::thread worker([&]() {
        while (keep_running.load()) {
#ifdef HAVE_IRIDESCENCE_VIEWER
            while (true) {
                {
                    std::lock_guard<std::mutex> lock(mtx_pause);
                    if (!is_paused) {
                        break;
                    }
                }
                {
                    std::lock_guard<std::mutex> lock(mtx_step);
                    if (step_count > 0) {
                        step_count--;
                        break;
                    }
                }
                std::this_thread::sleep_for(std::chrono::microseconds(5000));
            }
#endif

#ifdef HAVE_IRIDESCENCE_VIEWER
            {
                std::lock_guard<std::mutex> lock(mtx_terminate);
                if (terminate_is_requested) {
                    break;
                }
            }
#else
            if (slam->terminate_is_requested()) {
                break;
            }
#endif

            cv::Mat frame;
            try {
                if (!try_fetch_frame(client, request, source_opts.vehicle_name, frame)) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                    continue;
                }
            }
            catch (const std::exception& e) {
                spdlog::error("AirSim RPC error: {}", e.what());
                break;
            }

            if (frame.empty()) {
                continue;
            }
            if (scale != 1.0f) {
                cv::resize(frame, frame, cv::Size(), scale, scale, cv::INTER_LINEAR);
            }

            const auto tp_1 = std::chrono::steady_clock::now();

            const auto now = std::chrono::system_clock::now();
            const double timestamp = std::chrono::duration_cast<std::chrono::duration<double>>(now.time_since_epoch()).count();
            slam->feed_monocular_frame(frame, timestamp, mask);

            const auto tp_2 = std::chrono::steady_clock::now();
            const auto track_time = std::chrono::duration_cast<std::chrono::duration<double>>(tp_2 - tp_1).count();
            track_times.push_back(track_time);
        }

        keep_running = false;
        while (slam->loop_BA_is_running()) {
            std::this_thread::sleep_for(std::chrono::microseconds(5000));
        }
    });

    if (viewer_string == "pangolin_viewer") {
#ifdef HAVE_PANGOLIN_VIEWER
        viewer->run();
#endif
    }
    if (viewer_string == "iridescence_viewer") {
#ifdef HAVE_IRIDESCENCE_VIEWER
        iridescence_viewer->run();
#endif
    }
    if (viewer_string == "socket_publisher") {
#ifdef HAVE_SOCKET_PUBLISHER
        publisher->run();
#endif
    }

    keep_running = false;
    worker.join();

    slam->shutdown();

    if (!track_times.empty()) {
        std::sort(track_times.begin(), track_times.end());
        const auto total = std::accumulate(track_times.begin(), track_times.end(), 0.0);
        std::cout << "median tracking time: " << track_times.at(track_times.size() / 2) << "[s]" << std::endl;
        std::cout << "mean tracking time: " << total / track_times.size() << "[s]" << std::endl;
    }
    else {
        spdlog::warn("No tracking measurements were recorded.");
    }

    if (!map_db_path.empty()) {
        if (!slam->save_map_database(map_db_path)) {
            return EXIT_FAILURE;
        }
    }

    return EXIT_SUCCESS;
}

int main(int argc, char* argv[]) {
#ifdef USE_STACK_TRACE_LOGGER
    backward::SignalHandling sh;
#endif

    popl::OptionParser op("Allowed options");
    auto help = op.add<popl::Switch>("h", "help", "produce help message");
    auto vocab_file_path = op.add<popl::Value<std::string>>("v", "vocab", "vocabulary file path");
    auto without_vocab = op.add<popl::Switch>("", "without-vocab", "run without vocabulary file");
    auto config_file_path = op.add<popl::Value<std::string>>("c", "config", "config file path");
    auto mask_img_path = op.add<popl::Value<std::string>>("", "mask", "mask image path", "");
    auto scale = op.add<popl::Value<float>>("s", "scale", "scaling ratio of images", 1.0f);
    auto map_db_path_in = op.add<popl::Value<std::string>>("i", "map-db-in", "load a map from this path", "");
    auto map_db_path_out = op.add<popl::Value<std::string>>("o", "map-db-out", "store a map database at this path after slam", "");
    auto log_level = op.add<popl::Value<std::string>>("", "log-level", "log level", "info");
    auto disable_mapping = op.add<popl::Switch>("", "disable-mapping", "disable mapping");
    auto temporal_mapping = op.add<popl::Switch>("", "temporal-mapping", "enable temporal mapping");
    auto viewer = op.add<popl::Value<std::string>>("", "viewer", "viewer [iridescence_viewer, pangolin_viewer, socket_publisher, none]");
    auto vehicle_name = op.add<popl::Value<std::string>>("", "vehicle", "AirSim vehicle name", "Copter");
    auto camera_name = op.add<popl::Value<std::string>>("", "camera", "AirSim camera name", "Camera");
    auto airsim_host = op.add<popl::Value<std::string>>("", "airsim-host", "AirSim RPC host", "127.0.0.1");
    auto airsim_port = op.add<popl::Value<int>>("", "airsim-port", "AirSim RPC port", 41451);
    auto image_type = op.add<popl::Value<std::string>>("", "image-type", "AirSim image type [scene|depth|segmentation|infrared|disparity]", "scene");
    auto request_float = op.add<popl::Switch>("", "float", "Request floating point pixels (depth only)");
    auto request_compress = op.add<popl::Switch>("", "compress", "Request compressed PNG payload");
    try {
        op.parse(argc, argv);
    }
    catch (const std::exception& e) {
        std::cerr << e.what() << std::endl;
        std::cerr << std::endl;
        std::cerr << op << std::endl;
        return EXIT_FAILURE;
    }

    if (help->is_set()) {
        std::cerr << op << std::endl;
        return EXIT_FAILURE;
    }
    if (!op.unknown_options().empty()) {
        for (const auto& unknown_option : op.unknown_options()) {
            std::cerr << "unknown options: " << unknown_option << std::endl;
        }
        std::cerr << op << std::endl;
        return EXIT_FAILURE;
    }
    if ((!vocab_file_path->is_set() && !without_vocab->is_set()) || !config_file_path->is_set()) {
        std::cerr << "invalid arguments" << std::endl;
        std::cerr << std::endl;
        std::cerr << op << std::endl;
        return EXIT_FAILURE;
    }
    if (airsim_port->value() < 0 || airsim_port->value() > 65535) {
        std::cerr << "invalid AirSim port: " << airsim_port->value() << std::endl;
        return EXIT_FAILURE;
    }

    std::optional<ImageType> parsed_type = parse_image_type(image_type->value());
    if (!parsed_type) {
        std::cerr << "unknown AirSim image type: " << image_type->value() << std::endl;
        return EXIT_FAILURE;
    }

    std::string viewer_string;
    if (viewer->is_set()) {
        viewer_string = viewer->value();
        if (viewer_string != "pangolin_viewer"
            && viewer_string != "socket_publisher"
            && viewer_string != "iridescence_viewer"
            && viewer_string != "none") {
            std::cerr << "invalid arguments (--viewer)" << std::endl
                      << std::endl
                      << op << std::endl;
            return EXIT_FAILURE;
        }
#ifndef HAVE_PANGOLIN_VIEWER
        if (viewer_string == "pangolin_viewer") {
            std::cerr << "pangolin_viewer not linked" << std::endl
                      << std::endl
                      << op << std::endl;
            return EXIT_FAILURE;
        }
#endif
#ifndef HAVE_IRIDESCENCE_VIEWER
        if (viewer_string == "iridescence_viewer") {
            std::cerr << "iridescence_viewer not linked" << std::endl
                      << std::endl
                      << op << std::endl;
            return EXIT_FAILURE;
        }
#endif
#ifndef HAVE_SOCKET_PUBLISHER
        if (viewer_string == "socket_publisher") {
            std::cerr << "socket_publisher not linked" << std::endl
                      << std::endl
                      << op << std::endl;
            return EXIT_FAILURE;
        }
#endif
    }
    else {
#ifdef HAVE_IRIDESCENCE_VIEWER
        viewer_string = "iridescence_viewer";
#elif defined(HAVE_PANGOLIN_VIEWER)
        viewer_string = "pangolin_viewer";
#elif defined(HAVE_SOCKET_PUBLISHER)
        viewer_string = "socket_publisher";
#endif
    }

    spdlog::set_pattern("[%Y-%m-%d %H:%M:%S.%e] %^[%L] %v%$");
    spdlog::set_level(spdlog::level::from_str(log_level->value()));

    std::shared_ptr<stella_vslam::config> cfg;
    try {
        cfg = std::make_shared<stella_vslam::config>(config_file_path->value());
    }
    catch (const std::exception& e) {
        std::cerr << e.what() << std::endl;
        return EXIT_FAILURE;
    }

#ifdef USE_GOOGLE_PERFTOOLS
    ProfilerStart("slam.prof");
#endif

    std::string vocab_path = (without_vocab->is_set()) ? std::string() : vocab_file_path->value();
    auto slam = std::make_shared<stella_vslam::system>(cfg, vocab_path);
    bool need_initialize = true;
    if (map_db_path_in->is_set()) {
        need_initialize = false;
        const auto path = fs::path(map_db_path_in->value());
        if (path.extension() == ".yaml") {
            YAML::Node node = YAML::LoadFile(path);
            for (const auto& map_path : node["maps"].as<std::vector<std::string>>()) {
                if (!slam->load_map_database(path.parent_path() / map_path)) {
                    return EXIT_FAILURE;
                }
            }
        }
        else {
            if (!slam->load_map_database(path)) {
                return EXIT_FAILURE;
            }
        }
    }
    slam->startup(need_initialize);
    if (disable_mapping->is_set()) {
        slam->disable_mapping_module();
    }
    else if (temporal_mapping->is_set()) {
        slam->enable_temporal_mapping();
        slam->disable_loop_detector();
    }

    if (slam->get_camera()->setup_type_ != stella_vslam::camera::setup_type_t::Monocular) {
        spdlog::critical("run_camera_airsim_slam currently supports only monocular camera models.");
        slam->shutdown();
        return EXIT_FAILURE;
    }

    airsim_source_options source_opts;
    source_opts.vehicle_name = vehicle_name->value();
    source_opts.camera_name = camera_name->value();
    source_opts.rpc_address = airsim_host->value();
    source_opts.rpc_port = static_cast<std::uint16_t>(airsim_port->value());
    source_opts.image_type = *parsed_type;
    source_opts.pixels_as_float = request_float->is_set();
    source_opts.compress = request_compress->is_set();

    const int ret = mono_tracking(slam,
                                  cfg,
                                  source_opts,
                                  mask_img_path->value(),
                                  scale->value(),
                                  map_db_path_out->value(),
                                  viewer_string);

#ifdef USE_GOOGLE_PERFTOOLS
    ProfilerStop();
#endif

    return ret;
}
