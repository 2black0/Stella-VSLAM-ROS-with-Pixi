# 🗺️ Stella VSLAM with ROS 2 Humble (Pixi Environment)

**Stella VSLAM** is a modern Visual SLAM (Simultaneous Localization and Mapping) system that supports monocular, stereo, and RGB-D cameras. This repository provides a complete setup for building and running Stella VSLAM with **ROS 2 Humble** using **Pixi** for dependency management, eliminating the need for manual dependency installation.

![Stella-VSLAM-ROS2](assets/image-stella-vslam.png)

### ✨ Features

- 🎯 **Modern SLAM**: Based on ORB-SLAM with improvements and active maintenance
- 🤖 **ROS 2 Integration**: Full ROS 2 Humble support with topic-based communication
- 📦 **Pixi Environment**: Reproducible builds with isolated dependencies
- 🎮 **Multiple Viewers**: Support for Pangolin, Iridescence, and Socket viewers
- 🌐 **Multiple Camera Models**: Perspective, Fisheye, Equirectangular support

---

## 📋 Prerequisites

- **OS**: Linux (tested on Ubuntu 22.04)
- **Pixi**: [Install Pixi](https://pixi.sh/)

---

## 🚀 Quick Start

### 1️⃣ Setup Environment

```bash
pixi install
```

then activate the Pixi shell:

```bash
pixi shell
```

or run with `pixi run <command>`.

### 2️⃣ Vendored Dependencies

All required repos are already included under `lib/` and `ros2_ws/` (no submodules).

### 3️⃣ Build Viewer Dependencies

```bash
pixi run build-deps -- --all
```

To build only one viewer dependency:

```bash
pixi run build-deps -- --iridescence
pixi run build-deps -- --pangolin
pixi run build-deps -- --socket
```

### 4️⃣ Build Stella VSLAM Core + Examples

```bash
pixi run build -- --all
```

### 5️⃣ Build ROS 2 Wrapper (Optional)

```bash
pixi run build-ros
```

### 6️⃣ Download Example Dataset

```bash
pixi run dataset
```

This downloads:

- ORB vocabulary (`dataset/orb_vocab.fbow`)
- AIST Living Lab dataset (`dataset/aist_living_lab_1`)
- UZH-FPV dataset (`dataset/indoor_forward_3_snapdragon_with_gt`)
- UZH-FPV calibration (`dataset/indoor_forward_3_snapdragon_with_gt/indoor_forward_calib_snapdragon`)

### 7️⃣ Verify Build

```bash
pixi run check-deps
pixi run check
pixi run check-ros
pixi run check-dataset
```

---

## 🎮 Running Examples

### 🤖 ROS 2 Example (With Pangolin Viewer)

1. Terminal 1: Image Publisher

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 run image_publisher image_publisher_node dataset/aist_living_lab_1/video.mp4 --ros-args --remap /image_raw:=/camera/image_raw
```

2. Terminal 2: SLAM Node (Mapping)

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 run stella_vslam_ros run_slam -v dataset/orb_vocab.fbow -c lib/stella_vslam/example/aist/equirectangular.yaml --map-db-out map.msg --viewer pangolin_viewer --ros-args -p publish_tf:=false
```

File map.msg will be saved after finished.

3. Terminal 2: Localization Mode (Load Map)

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 run stella_vslam_ros run_slam --disable-mapping -v dataset/orb_vocab.fbow -c lib/stella_vslam/example/aist/equirectangular.yaml --map-db-in map.msg --viewer pangolin_viewer --ros-args -p publish_tf:=false
```

Load map.msg that saved from process before.

📡 ROS 2 Topics

```
/camera/image_raw           # Input image
/run_slam/camera_pose       # Camera pose (Odometry)
/run_slam/keyframes         # Keyframes
/tf                         # Transform tree
```

### 🧩 ROS 2 Composable (Intra-Process, Zero-Copy Friendly)

All nodes run in a single process to avoid DDS serialization (faster for large videos).

1. Terminal 1: Run component container with intra-process communication

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 run rclcpp_components component_container_mt --ros-args -r __node:=slam_container -p use_intra_process_comms:=true
```

2. Terminal 2: Load SLAM with Pangolin

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 component load /slam_container stella_vslam_ros stella_vslam_ros::System --node-name run_slam --param vocab_file_path:=dataset/orb_vocab.fbow --param setting_file_path:=lib/stella_vslam/example/aist/equirectangular.yaml --param map_db_path_out:=map.msg --param viewer:=pangolin_viewer --param publish_tf:=false --param encoding:=bgr8 --param qos_reliability:=reliable
```

3. Terminal 3: Load video publisher (adjust video path if needed)

```bash
pixi shell
source ros2_ws/install/setup.bash
ros2 component load /slam_container stella_vslam_ros stella_vslam_ros::VideoPublisher --node-name video_pub --param video_path:=dataset/aist_living_lab_1/video.mp4 --param topic:=camera/image_raw --param frame_id:=camera --param fps:=0.0 --param loop:=true
```

Pangolin will appear; this pipeline uses intra-process communications to avoid copy/serialization between processes.

### ⚡ Non-ROS Example (Direct Video Processing)

### 🎥 AIST Living Lab Equirectangular (Video File)

Dataset: `dataset/aist_living_lab_1/video.mp4`

Run SLAM directly without ROS middleware:

```bash
pixi run test-aist
```

Manual (inside Pixi shell):

```bash
pixi shell
bash scripts/test-aist.sh
```

This script automatically:

- Builds `stella_vslam_examples`
- Runs `run_video_slam` with Pangolin Viewer

Direct `run_video_slam` invocation:

```bash
pixi shell
./lib/stella_vslam_examples/build/run_video_slam \
    -v dataset/orb_vocab.fbow \
    -m dataset/aist_living_lab_1/video.mp4 \
    -c lib/stella_vslam/example/aist/equirectangular.yaml \
    --map-db-out map.msg \
    --frame-skip 2 \
    --viewer pangolin_viewer \
    --no-sleep
```

#### 🏂 UZH-FPV Monocular (Image Sequence)

Dataset: UZH-FPV FPV/VIO dataset — download sequences from https://fpv.ifi.uzh.ch/datasets/

Run monocular image-sequence SLAM:

```bash
pixi run test-uzh
```

Manual (inside Pixi shell):

```bash
pixi shell
bash scripts/test-uzh.sh
```

What the script does:

- Resolves relative dataset paths (e.g., `dataset/...`) against the repo root
- Uses `left_images.txt` (cam0/left) to create a temporary ordered symlink sequence (cleaned up on exit)
- Image order follows the sequence in `left_images.txt`, not filename sorting in `<dataset>/img`
- Uses config `lib/stella_vslam/example/uzh_fpv/UZH_FPV_mono.yaml` and vocab `dataset/orb_vocab.fbow`
- Runs `run_image_slam` (Pangolin viewer, frame-skip 1)

### 🚁 AirSim Example (Real-time with Simulator)

Run SLAM with **AirSim simulator** as camera input source:

#### Prerequisites:

1. **AirSim simulator running** (Unreal Engine or Unity)
2. **ORB vocabulary**: `dataset/orb_vocab.fbow`
3. **Camera config**: Create appropriate YAML config for your AirSim camera

#### Run:

```bash
pixi shell
./bin/run_camera_airsim_slam \
    -v dataset/orb_vocab.fbow \
    -c config/airsim-1280x720.yaml \
    --viewer pangolin_viewer \
    --airsim-host 127.0.0.1 \
    --airsim-port 41451
```

#### AirSim-specific Arguments:

```
--airsim-host arg (=127.0.0.1)    AirSim server IP address
--airsim-port arg (=41451)         AirSim RPC port
--vehicle arg (=)                  Vehicle name (empty for default)
--camera arg (=0)                  Camera name/ID
```

**Note:** The executable is available at `bin/run_camera_airsim_slam` or `lib/stella_vslam_examples/build/run_camera_airsim_slam`

---

## ⚙️ Command-Line Arguments

### For `run_slam` (ROS 2)

```
-v, --vocab arg             vocabulary file path
-c, --config arg            config file path
--mask arg                  mask image path
--map-db-in arg             load a map from this path
--map-db-out arg            store a map database at this path after SLAM
--disable-mapping           disable mapping module
--temporal-mapping          enable temporal mapping
--viewer arg                viewer type (pangolin_viewer, iridescence_viewer, socket_publisher, none)
--log-level arg (=info)     log level

ROS 2 Parameters:
--ros-args -p publish_tf:=<true|false>              publish TF transforms
--ros-args -p odom_frame:=<frame_name>              odometry frame name
--ros-args -p map_frame:=<frame_name>               map frame name
--ros-args -p camera_frame:=<frame_name>            camera frame name
```

### For `run_video_slam` (Non-ROS)

```
-h, --help                  produce help message
-v, --vocab arg             vocabulary file path
-m, --video arg             video file path
-c, --config arg            config file path
--mask arg                  mask image path
--frame-skip arg (=1)       interval of frame skip
--no-sleep                  not wait for next frame in real time
--auto-term                 automatically terminate the viewer
--log-level arg (=info)     log level (trace, debug, info, warn, err, critical, off)
--map-db-in arg             load a map from this path
--map-db-out arg            store a map database at this path after SLAM
--disable-mapping           disable mapping module
--temporal-mapping          enable temporal mapping
```

### For `run_euroc_slam` (Image Sequence)

```
-h, --help                  produce help message
-v, --vocab arg             vocabulary file path
-d, --data-dir arg          directory path which contains dataset
-c, --config arg            config file path
--frame-skip arg (=1)       interval of frame skip
--no-sleep                  not wait for next frame in real time
--auto-term                 automatically terminate the viewer
--log-level arg (=info)     log level (trace, debug, info, warn, err, critical, off)
--eval-log-dir arg          store trajectories + tracking times (TUM format; dir must exist)
--map-db-in arg             load a map from this path
--map-db-out arg            store a map database at this path after SLAM
--disable-mapping           disable mapping module
--temporal-mapping          enable temporal mapping
--equal-hist                apply histogram equalization
--viewer arg                viewer type (pangolin_viewer, iridescence_viewer, socket_publisher, none)
```

---

## 📁 Project Structure

```
stella-vslam-ros-with-pixi/
├── assets/
│   └── image-stella-vslam.png
├── dataset/
│   ├── orb_vocab.fbow
│   ├── aist_living_lab_1/
│   └── indoor_forward_3_snapdragon_with_gt/
│       └── indoor_forward_calib_snapdragon/
├── lib/
│   ├── AirSim/
│   ├── iridescence/
│   ├── iridescence_viewer/
│   ├── Pangolin/
│   ├── pangolin_viewer/
│   ├── socket.io-client-cpp/
│   ├── socket_publisher/
│   ├── socket_viewer/
│   ├── stella_vslam/
│   └── stella_vslam_examples/
│       └── build/
│           ├── run_camera_airsim_slam
│           ├── run_camera_slam
│           └── ... (other examples)
├── ros2_ws/
│   └── src/stella_vslam_ros/
├── scripts/
│   ├── build-deps.sh           # Build viewer dependencies + AirSim deps
│   ├── build.sh                # Build stella_vslam core + examples
│   ├── build-ros.sh            # Build ROS 2 wrapper
│   ├── check-dataset.sh        # Verify dataset layout
│   ├── check-deps.sh           # Verify build dependencies
│   ├── check.sh                # Verify core build + examples
│   ├── check-ros.sh            # Verify ROS 2 build
│   ├── dataset.sh              # Download dataset
│   ├── test-aist.sh            # Run AIST Living Lab example 
│   ├── test-uzh.sh             # Run UZH-FPV example
│   └── clean.sh                # Clean build artifacts
└── pixi.toml                   # Pixi configuration
```

Note: for this project, all non-build files in vendored libraries have been pruned/deleted.

---

## 🛠️ Troubleshooting

### Build Fails

```bash
bash scripts/clean.sh
pixi install
pixi run build-deps -- --all
pixi run build -- --all
pixi run build-ros
```

### Viewer Not Showing

- Make sure you're running in a desktop environment with GUI support
- Check that the `--viewer pangolin_viewer` flag is included

---

## 📚 References

Vendored libraries under `lib/`:
- [AirSim](https://github.com/microsoft/AirSim) (`lib/AirSim`)
- [iridescence](https://github.com/koide3/iridescence) (`lib/iridescence`)
- [iridescence_viewer](https://github.com/stella-cv/iridescence_viewer) (`lib/iridescence_viewer`)
- [Pangolin](https://github.com/stevenlovegrove/Pangolin) (`lib/Pangolin`)
- [pangolin_viewer](https://github.com/stella-cv/pangolin_viewer) (`lib/pangolin_viewer`)
- [socket.io-client-cpp](https://github.com/socketio/socket.io-client-cpp) (`lib/socket.io-client-cpp`)
- [socket_publisher](https://github.com/stella-cv/socket_publisher) (`lib/socket_publisher`)
- [socket_viewer](https://github.com/stella-cv/socket_viewer) (`lib/socket_viewer`)
- [Stella VSLAM](https://github.com/stella-cv/stella_vslam) (`lib/stella_vslam`)
- [stella_vslam_examples](https://github.com/stella-cv/stella_vslam_examples) (`lib/stella_vslam_examples`)

Other references:
- [Stella VSLAM ROS](https://github.com/stella-cv/stella_vslam_ros)
- [Pixi Package Manager](https://pixi.sh/)

<details>
  <summary>Original README</summary>

# stella_vslam

[![CI](https://github.com/stella-cv/stella_vslam/actions/workflows/main.yml/badge.svg)](https://github.com/stella-cv/stella_vslam/actions/workflows/main.yml)
[![Documentation Status](https://readthedocs.org/projects/stella-cv/badge/?version=latest)](https://stella-cv.readthedocs.io/en/latest/?badge=latest)
[![License](https://img.shields.io/badge/License-BSD%202--Clause-orange.svg)](https://opensource.org/licenses/BSD-2-Clause)

---

> _NOTE:_ This is a community fork of [xdspacelab/openvslam](https://github.com/xdspacelab/openvslam). It was created to continue active development of OpenVSLAM on Jan 31, 2021. The original repository is no longer available. Please read the [official statement of termination](https://github.com/xdspacelab/openvslam/wiki/Termination-of-the-release) carefully and understand it before using this. The similarities with ORB_SLAM2 in the original version have been removed by [#252](https://github.com/stella-cv/stella_vslam/pull/252). If you find any other issues with the license, please point them out. See [#37](https://github.com/stella-cv/stella_vslam/issues/37) and [#249](https://github.com/stella-cv/stella_vslam/issues/249) for discussion so far.

_Versions earlier than 0.3 are deprecated. If you use them, please use them as a derivative of ORB_SLAM2 under the GPL license._

---

## Overview

[<img src="https://raw.githubusercontent.com/stella-cv/docs/main/docs/img/teaser.png" width="640px">](https://arxiv.org/abs/1910.01122)

<img src="https://j.gifs.com/81m1QL.gif" width="640px">

[**[PrePrint]**](https://arxiv.org/abs/1910.01122)

stella_vslam is a monocular, stereo, and RGBD visual SLAM system.

### Features

The notable features are:

- It is compatible with **various type of camera models** and can be easily customized for other camera models.
- Created maps can be **stored and loaded**, then stella_vslam can **localize new images** based on the prebuilt maps.
- The system is fully modular. It is designed by encapsulating several functions in separated components with easy-to-understand APIs.
- We provided **some code snippets** to understand the core functionalities of this system.

One of the noteworthy features of stella_vslam is that the system can deal with various type of camera models, such as perspective, fisheye, and equirectangular.
If needed, users can implement extra camera models (e.g. dual fisheye, catadioptric) with ease.
For example, visual SLAM algorithm using **equirectangular camera models** (e.g. RICOH THETA series, insta360 series, etc) is shown above.

We provided [documentation](https://stella-cv.readthedocs.io/) for installation and tutorial.
The repository for the ROS wrapper is [stella_vslam_ros](https://github.com/stella-cv/stella_vslam_ros).

### Acknowledgements

OpenVSLAM is based on an indirect SLAM algorithm with sparse features, such as [ORB-SLAM](https://arxiv.org/abs/1502.00956)/[ORB-SLAM2](https://arxiv.org/abs/1610.06475), [ProSLAM](https://arxiv.org/abs/1709.04377), and [UcoSLAM](https://arxiv.org/abs/1902.03729).
The core architecture is based on ORB-SLAM/ORB-SLAM2 and the code has been redesigned and written from scratch to improve scalability, readability, performance, etc.
UcoSLAM has implemented the parallelization of feature extraction, map storage and loading earlier.
ProSLAM has implemented a highly modular and easily understood system earlier.

### Examples

Some code snippets to understand the core functionalities of the system are provided.
You can employ these snippets for in your own programs.
Please see the `*.cc` files in `./example` directory or check [Simple Tutorial](https://stella-cv.readthedocs.io/en/latest/simple_tutorial.html) and [Example](https://stella-cv.readthedocs.io/en/latest/example.html).

## Installation

Please see [**Installation**](https://stella-cv.readthedocs.io/en/latest/installation.html) chapter in the [documentation](https://stella-cv.readthedocs.io/).

[**The instructions for Docker users**](https://stella-cv.readthedocs.io/en/latest/docker.html) are also provided.

## Tutorial

Please see [**Simple Tutorial**](https://stella-cv.readthedocs.io/en/latest/simple_tutorial.html) chapter in the [documentation](https://stella-cv.readthedocs.io/).

A sample ORB vocabulary file can be downloaded from [here](https://github.com/stella-cv/FBoW_orb_vocab/raw/main/orb_vocab.fbow).
Sample datasets are also provided at [here](https://drive.google.com/open?id=1A_gq8LYuENePhNHsuscLZQPhbJJwzAq4).

If you would like to run visual SLAM with standard benchmarking datasets (e.g. KITTI Odometry dataset), please see [**SLAM with standard datasets**](https://stella-cv.readthedocs.io/en/latest/example.html#slam-with-standard-datasets) section in the [documentation](https://stella-cv.readthedocs.io/).

## Community

Please contact us via [GitHub Discussions](https://github.com/stella-cv/stella_vslam/discussions) if you have any questions or notice any bugs about the software.

## Currently working on

- Refactoring
- Algorithm changes and parameter additions to improve performance
- Add tests
- Marker integration
- Implementation of extra camera models
- Python bindings
- IMU integration

The higher up the list, the higher the priority.
Feedbacks, feature requests, and contribution are welcome!

## License

**2-clause BSD license** (see [LICENSE](./LICENSE))

The following files are derived from third-party libraries.

- `./3rd/json` : [nlohmann/json \[v3.6.1\]](https://github.com/nlohmann/json) (MIT license)
- `./3rd/spdlog` : [gabime/spdlog \[v1.3.1\]](https://github.com/gabime/spdlog) (MIT license)
- `./3rd/tinycolormap` : [yuki-koyama/tinycolormap](https://github.com/yuki-koyama/tinycolormap) (MIT license)
- `./3rd/FBoW` : [stella-cv/FBoW](https://github.com/stella-cv/FBoW) (MIT license) (forked from [rmsalinas/fbow](https://github.com/rmsalinas/fbow))
- `./src/stella_vslam/solver/essential_5pt.h` : part of [libmv/libmv](https://github.com/libmv/libmv) (MIT license)
- `./src/stella_vslam/solver/pnp_solver.cc` : part of [laurentkneip/opengv](https://github.com/laurentkneip/opengv) (3-clause BSD license)
- `./src/stella_vslam/feature/orb_extractor.cc` : part of [opencv/opencv](https://github.com/opencv/opencv) (3-clause BSD License)
- `./src/stella_vslam/feature/orb_point_pairs.h` : part of [opencv/opencv](https://github.com/opencv/opencv) (3-clause BSD License)

Please use `g2o` as the dynamic link library because `csparse_extension` module of `g2o` is LGPLv3+.

## Authors of the original version of OpenVSLAM

- Shinya Sumikura ([@shinsumicco](https://github.com/shinsumicco))
- Mikiya Shibuya ([@MikiyaShibuya](https://github.com/MikiyaShibuya))
- Ken Sakurada ([@kensakurada](https://github.com/kensakurada))

## Citation of original version of OpenVSLAM

OpenVSLAM **won first place** at **ACM Multimedia 2019 Open Source Software Competition**.

If OpenVSLAM helps your research, please cite the paper for OpenVSLAM. Here is a BibTeX entry:

```
@inproceedings{openvslam2019,
  author = {Sumikura, Shinya and Shibuya, Mikiya and Sakurada, Ken},
  title = {{OpenVSLAM: A Versatile Visual SLAM Framework}},
  booktitle = {Proceedings of the 27th ACM International Conference on Multimedia},
  series = {MM '19},
  year = {2019},
  isbn = {978-1-4503-6889-6},
  location = {Nice, France},
  pages = {2292--2295},
  numpages = {4},
  url = {http://doi.acm.org/10.1145/3343031.3350539},
  doi = {10.1145/3343031.3350539},
  acmid = {3350539},
  publisher = {ACM},
  address = {New York, NY, USA}
}
```

The preprint can be found [here](https://arxiv.org/abs/1910.01122).

## Reference

- Raúl Mur-Artal, J. M. M. Montiel, and Juan D. Tardós. 2015. ORB-SLAM: a Versatile and Accurate Monocular SLAM System. IEEE Transactions on Robotics 31, 5 (2015), 1147–1163.
- Raúl Mur-Artal and Juan D. Tardós. 2017. ORB-SLAM2: an Open-Source SLAM System for Monocular, Stereo and RGB-D Cameras. IEEE Transactions on Robotics 33, 5 (2017), 1255–1262.
- Dominik Schlegel, Mirco Colosi, and Giorgio Grisetti. 2018. ProSLAM: Graph SLAM from a Programmer’s Perspective. In Proceedings of IEEE International Conference on Robotics and Automation (ICRA). 1–9.
- Rafael Muñoz-Salinas and Rafael Medina Carnicer. 2019. UcoSLAM: Simultaneous Localization and Mapping by Fusion of KeyPoints and Squared Planar Markers. arXiv:1902.03729.
- Mapillary AB. 2019. OpenSfM. <https://github.com/mapillary/OpenSfM>.
- Giorgio Grisetti, Rainer Kümmerle, Cyrill Stachniss, and Wolfram Burgard. 2010. A Tutorial on Graph-Based SLAM. IEEE Transactions on Intelligent Transportation SystemsMagazine 2, 4 (2010), 31–43.
- Rainer Kümmerle, Giorgio Grisetti, Hauke Strasdat, Kurt Konolige, and Wolfram Burgard. 2011. g2o: A general framework for graph optimization. In Proceedings of IEEE International Conference on Robotics and Automation (ICRA). 3607–3613.

</details>
