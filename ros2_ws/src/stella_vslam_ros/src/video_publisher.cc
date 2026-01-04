#include <rclcpp/rclcpp.hpp>
#include <rclcpp_components/register_node_macro.hpp>
#include <sensor_msgs/msg/image.hpp>
#include <cv_bridge/cv_bridge.h>
#include <image_transport/image_transport.hpp>
#include <opencv2/core/core.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/videoio.hpp>

namespace stella_vslam_ros {

class VideoPublisher : public rclcpp::Node {
public:
    explicit VideoPublisher(const rclcpp::NodeOptions& options = rclcpp::NodeOptions())
        : Node("video_publisher", options) {
        video_path_ = declare_parameter<std::string>("video_path", "");
        topic_ = declare_parameter<std::string>("topic", "camera/image_raw");
        frame_id_ = declare_parameter<std::string>("frame_id", "camera");
        fps_param_ = declare_parameter<double>("fps", 0.0); // 0 -> use video fps
        loop_ = declare_parameter<bool>("loop", true);

        if (video_path_.empty()) {
            RCLCPP_FATAL(get_logger(), "video_path parameter is required");
            throw std::runtime_error("video_path missing");
        }

        cap_.open(video_path_);
        if (!cap_.isOpened()) {
            RCLCPP_FATAL(get_logger(), "Failed to open video: %s", video_path_.c_str());
            throw std::runtime_error("open video failed");
        }

        double fps = fps_param_;
        if (fps <= 0.0) {
            fps = cap_.get(cv::CAP_PROP_FPS);
            if (fps <= 0.0) {
                fps = 30.0; // fallback
            }
        }
        period_ = std::chrono::duration<double>(1.0 / fps);

        auto qos = rclcpp::QoS(rclcpp::KeepLast(10)).reliable().durability_volatile();
        pub_ = image_transport::create_publisher(this, topic_, qos.get_rmw_qos_profile());

        timer_ = create_wall_timer(std::chrono::duration_cast<std::chrono::nanoseconds>(period_), std::bind(&VideoPublisher::tick, this));
        RCLCPP_INFO(get_logger(), "VideoPublisher started: %s @ %.2f FPS -> %s", video_path_.c_str(), fps, topic_.c_str());
    }

private:
    void tick() {
        cv::Mat frame;
        if (!cap_.read(frame)) {
            if (loop_) {
                cap_.set(cv::CAP_PROP_POS_FRAMES, 0);
                if (!cap_.read(frame)) {
                    RCLCPP_ERROR(get_logger(), "Failed to read frame after loop restart");
                    return;
                }
            }
            else {
                RCLCPP_INFO(get_logger(), "End of video reached, stopping timer");
                timer_->cancel();
                return;
            }
        }

        auto msg = cv_bridge::CvImage(std_msgs::msg::Header(), "bgr8", frame).toImageMsg();
        msg->header.stamp = now();
        msg->header.frame_id = frame_id_;
        pub_.publish(msg);
    }

    std::string video_path_;
    std::string topic_;
    std::string frame_id_;
    double fps_param_{0.0};
    bool loop_{true};
    cv::VideoCapture cap_;
    std::chrono::duration<double> period_;
    image_transport::Publisher pub_;
    rclcpp::TimerBase::SharedPtr timer_;
};

} // namespace stella_vslam_ros

RCLCPP_COMPONENTS_REGISTER_NODE(stella_vslam_ros::VideoPublisher)
