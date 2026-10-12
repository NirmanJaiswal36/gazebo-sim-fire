import os

from launch import LaunchDescription
from launch.actions import ExecuteProcess, TimerAction
from launch_ros.actions import Node


# ==========================================================
# PATHS
# ==========================================================

PX4_DIR = "/home/swadhin/PX4-Autopilot"

PX4_BIN = os.path.join(
    PX4_DIR,
    "build/px4_sitl_default/bin/px4"
)

WORLD = os.path.join(
    PX4_DIR,
    "Tools/simulation/gz/worlds/forest.sdf"
)

GZ_MODELS = os.path.join(
    PX4_DIR,
    "Tools/simulation/gz/models"
)

GZ_WORLDS = os.path.join(
    PX4_DIR,
    "Tools/simulation/gz/worlds"
)

RESOURCE_PATH = GZ_MODELS + ":" + GZ_WORLDS


# ==========================================================
# LAUNCH DESCRIPTION
# ==========================================================

def generate_launch_description():

    # ======================================================
    # MICRO XRCE DDS AGENT
    # ======================================================

    xrce = ExecuteProcess(
        cmd=[
            "MicroXRCEAgent",
            "udp4",
            "-p",
            "8888"
        ],
        output="screen"
    )


    # ======================================================
    # GAZEBO
    #
    # Only ONE Gazebo instance
    # ======================================================

    gazebo = ExecuteProcess(
        cmd=[
            "gz",
            "sim",
            "-r",
            WORLD
        ],

        additional_env={
            "GZ_SIM_RESOURCE_PATH": RESOURCE_PATH,
        },

        output="screen"
    )


    # ======================================================
    # PX4 UAV 0
    #
    # Instance:
    #     0
    #
    # Model:
    #     gz_x500_depth
    #
    # Pose:
    #     x=0 y=0 z=0.5
    # ======================================================

    px4_0 = ExecuteProcess(
        cmd=[
            PX4_BIN,
            "-i",
            "0"
        ],

        cwd=PX4_DIR,

        additional_env={

            "PX4_SYS_AUTOSTART": "4002",

            "PX4_SIM_MODEL": "gz_x500_depth",

            "PX4_GZ_STANDALONE": "1",

            "PX4_GZ_MODEL_POSE": "0,0,0.5,0,0,0",

            "PX4_UXRCE_DDS_PORT": "8888",

            "GZ_SIM_RESOURCE_PATH": RESOURCE_PATH,
        },

        output="screen"
    )


    # ======================================================
    # PX4 UAV 1
    #
    # Instance:
    #     1
    #
    # Model:
    #     gz_x500_depth
    #
    # Pose:
    #     x=5 y=0 z=0.5
    # ======================================================

    px4_1 = ExecuteProcess(
        cmd=[
            PX4_BIN,
            "-i",
            "1"
        ],

        cwd=PX4_DIR,

        additional_env={

            "PX4_SYS_AUTOSTART": "4002",

            "PX4_SIM_MODEL": "gz_x500_depth",

            "PX4_GZ_STANDALONE": "1",

            "PX4_GZ_MODEL_POSE": "5,0,0.5,0,0,0",

            "PX4_UXRCE_DDS_PORT": "8888",

            "PX4_UXRCE_DDS_NS": "px4_1",

            "GZ_SIM_RESOURCE_PATH": RESOURCE_PATH,
        },

        output="screen"
    )


    # ======================================================
    # CAMERA UAV 0
    # ======================================================

    camera0 = Node(
        package="ros_gz_bridge",
        executable="parameter_bridge",

        arguments=[
            "/world/forest/"
            "model/x500_depth_0/"
            "link/camera_link/"
            "sensor/IMX214/image"
            "@sensor_msgs/msg/Image"
            "[gz.msgs.Image"
        ],

        remappings=[
            (
                "/world/forest/"
                "model/x500_depth_0/"
                "link/camera_link/"
                "sensor/IMX214/image",

                "/uav1/camera/image"
            )
        ],

        output="screen"
    )


    # ======================================================
    # CAMERA UAV 1
    # ======================================================

    camera1 = Node(
        package="ros_gz_bridge",
        executable="parameter_bridge",

        arguments=[
            "/world/forest/"
            "model/x500_depth_1/"
            "link/camera_link/"
            "sensor/IMX214/image"
            "@sensor_msgs/msg/Image"
            "[gz.msgs.Image"
        ],

        remappings=[
            (
                "/world/forest/"
                "model/x500_depth_1/"
                "link/camera_link/"
                "sensor/IMX214/image",

                "/uav2/camera/image"
            )
        ],

        output="screen"
    )


    # ======================================================
    # ARM UAV 0
    # ======================================================

    arm0 = ExecuteProcess(
        cmd=[
            "ros2",
            "topic",
            "pub",
            "--once",
            "/fmu/in/vehicle_command",
            "px4_msgs/msg/VehicleCommand",

            "{"
            "timestamp: 0,"
            "command: 400,"
            "param1: 1.0,"
            "target_system: 1,"
            "target_component: 1,"
            "source_system: 1,"
            "source_component: 1,"
            "from_external: true"
            "}"
        ],

        output="screen"
    )


    # ======================================================
    # ARM UAV 1
    # ======================================================

    arm1 = ExecuteProcess(
        cmd=[
            "ros2",
            "topic",
            "pub",
            "--once",
            "/px4_1/fmu/in/vehicle_command",
            "px4_msgs/msg/VehicleCommand",

            "{"
            "timestamp: 0,"
            "command: 400,"
            "param1: 1.0,"
            "target_system: 2,"
            "target_component: 1,"
            "source_system: 1,"
            "source_component: 1,"
            "from_external: true"
            "}"
        ],

        output="screen"
    )


    # ======================================================
    # TAKEOFF UAV 0
    # ======================================================

    takeoff0 = ExecuteProcess(
        cmd=[
            "ros2",
            "topic",
            "pub",
            "--once",
            "/fmu/in/vehicle_command",
            "px4_msgs/msg/VehicleCommand",

            "{"
            "timestamp: 0,"
            "command: 22,"
            "param7: 2.0,"
            "target_system: 1,"
            "target_component: 1,"
            "source_system: 1,"
            "source_component: 1,"
            "from_external: true"
            "}"
        ],

        output="screen"
    )


    # ======================================================
    # TAKEOFF UAV 1
    # ======================================================

    takeoff1 = ExecuteProcess(
        cmd=[
            "ros2",
            "topic",
            "pub",
            "--once",
            "/px4_1/fmu/in/vehicle_command",
            "px4_msgs/msg/VehicleCommand",

            "{"
            "timestamp: 0,"
            "command: 22,"
            "param7: 2.0,"
            "target_system: 2,"
            "target_component: 1,"
            "source_system: 1,"
            "source_component: 1,"
            "from_external: true"
            "}"
        ],

        output="screen"
    )


    # ======================================================
    # START PX4
    #
    # Gazebo must be running first.
    # ======================================================

    px4_processes = TimerAction(
        period=5.0,
        actions=[
            px4_0,
            px4_1
        ]
    )


    # ======================================================
    # CAMERA BRIDGES
    #
    # Give PX4/Gazebo time to spawn models.
    # ======================================================

    camera_processes = TimerAction(
        period=10.0,
        actions=[
            camera0,
            camera1
        ]
    )


    # ======================================================
    # ARM
    # ======================================================

    arm_processes = TimerAction(
        period=15.0,
        actions=[
            arm0,
            arm1
        ]
    )


    # ======================================================
    # TAKEOFF
    # ======================================================

    takeoff_processes = TimerAction(
        period=18.0,
        actions=[
            takeoff0,
            takeoff1
        ]
    )


    # ======================================================
    # FINAL LAUNCH
    # ======================================================

    return LaunchDescription([

        xrce,

        gazebo,

        px4_processes,

        camera_processes,

        arm_processes,

        takeoff_processes,
    ])
