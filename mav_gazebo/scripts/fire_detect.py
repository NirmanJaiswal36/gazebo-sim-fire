#!/usr/bin/env python3

import rclpy
from rclpy.node import Node

from sensor_msgs.msg import Image
from cv_bridge import CvBridge

import cv2
import numpy as np


class OrangeCircleDetector(Node):

    def __init__(self):
        super().__init__('orange_circle_detector')

        self.bridge = CvBridge()

        # =========================================================
        # INPUT IMAGE TOPICS
        # =========================================================

        self.topics = [
            '/drone_0/camera/image_raw',
            '/drone_1/camera/image_raw',
            '/drone_2/camera/image_raw',
            '/drone_3/camera/image_raw',
            '/drone_4/camera/image_raw',
        ]

        # =========================================================
        # ROS SUBSCRIBERS AND PUBLISHERS
        # =========================================================

        self.subscriptions = []
        self.publishers = {}

        for topic in self.topics:

            # Input topic -> output topic
            output_topic = topic.replace(
                '/image_raw',
                '/orange_circle_detection'
            )

            # -----------------------------------------------------
            # Subscriber
            # -----------------------------------------------------

            sub = self.create_subscription(
                Image,
                topic,
                lambda msg, t=topic: self.image_callback(msg, t),
                10
            )

            self.subscriptions.append(sub)

            # -----------------------------------------------------
            # Publisher
            # -----------------------------------------------------

            pub = self.create_publisher(
                Image,
                output_topic,
                10
            )

            self.publishers[topic] = pub

            self.get_logger().info(
                f'Input : {topic}'
            )

            self.get_logger().info(
                f'Output: {output_topic}'
            )

        # =========================================================
        # ORANGE HSV RANGE
        # =========================================================

        self.orange_lower = np.array([
            5,     # Hue
            100,   # Saturation
            100    # Value
        ])

        self.orange_upper = np.array([
            25,
            255,
            255
        ])

        # Minimum orange contour area
        self.min_area = 100

        # Minimum circularity
        self.min_circularity = 0.65

    # =============================================================
    # IMAGE CALLBACK
    # =============================================================

    def image_callback(self, msg, topic):

        try:

            frame = self.bridge.imgmsg_to_cv2(
                msg,
                desired_encoding='bgr8'
            )

        except Exception as e:

            self.get_logger().error(
                f'CV bridge error [{topic}]: {e}'
            )

            return

        # ---------------------------------------------------------
        # Detect orange circle
        # ---------------------------------------------------------

        detection = self.detect_orange_circle(frame)

        # ---------------------------------------------------------
        # Draw detection
        # ---------------------------------------------------------

        if detection is not None:

            x, y, radius, area, circularity = detection

            cv2.circle(
                frame,
                (x, y),
                radius,
                (0, 255, 0),
                3
            )

            # Center point
            cv2.circle(
                frame,
                (x, y),
                5,
                (255, 0, 0),
                -1
            )

            cv2.putText(
                frame,
                'ORANGE CIRCLE',
                (x - 70, y - radius - 10),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 255, 0),
                2
            )

            self.get_logger().info(
                f'[{topic}] '
                f'Detected: center=({x},{y}), '
                f'radius={radius}, '
                f'area={area:.0f}, '
                f'circularity={circularity:.2f}'
            )

        # ---------------------------------------------------------
        # Publish processed image
        # ---------------------------------------------------------

        output_msg = self.bridge.cv2_to_imgmsg(
            frame,
            encoding='bgr8'
        )

        # Preserve original timestamp
        output_msg.header = msg.header

        self.publishers[topic].publish(output_msg)

    # =============================================================
    # ORANGE CIRCLE DETECTOR
    # =============================================================

    def detect_orange_circle(self, frame):

        # ---------------------------------------------------------
        # BGR -> HSV
        # ---------------------------------------------------------

        hsv = cv2.cvtColor(
            frame,
            cv2.COLOR_BGR2HSV
        )

        # ---------------------------------------------------------
        # Orange mask
        # ---------------------------------------------------------

        mask = cv2.inRange(
            hsv,
            self.orange_lower,
            self.orange_upper
        )

        # ---------------------------------------------------------
        # Morphological filtering
        # ---------------------------------------------------------

        kernel = np.ones(
            (5, 5),
            np.uint8
        )

        mask = cv2.morphologyEx(
            mask,
            cv2.MORPH_OPEN,
            kernel
        )

        mask = cv2.morphologyEx(
            mask,
            cv2.MORPH_CLOSE,
            kernel
        )

        # ---------------------------------------------------------
        # Find contours
        # ---------------------------------------------------------

        contours, _ = cv2.findContours(
            mask,
            cv2.RETR_EXTERNAL,
            cv2.CHAIN_APPROX_SIMPLE
        )

        best_detection = None
        best_score = 0

        for contour in contours:

            area = cv2.contourArea(contour)

            if area < self.min_area:
                continue

            perimeter = cv2.arcLength(
                contour,
                True
            )

            if perimeter == 0:
                continue

            # -----------------------------------------------------
            # Circularity
            # -----------------------------------------------------

            circularity = (
                4.0 * np.pi * area /
                (perimeter * perimeter)
            )

            if circularity < self.min_circularity:
                continue

            # -----------------------------------------------------
            # Enclosing circle
            # -----------------------------------------------------

            (cx, cy), radius = cv2.minEnclosingCircle(
                contour
            )

            cx = int(cx)
            cy = int(cy)
            radius = int(radius)

            # -----------------------------------------------------
            # Solidity
            # -----------------------------------------------------

            hull = cv2.convexHull(contour)

            hull_area = cv2.contourArea(hull)

            if hull_area == 0:
                continue

            solidity = area / hull_area

            if solidity < 0.80:
                continue

            # -----------------------------------------------------
            # Candidate score
            # -----------------------------------------------------

            score = (
                area *
                circularity *
                solidity
            )

            if score > best_score:

                best_score = score

                best_detection = (
                    cx,
                    cy,
                    radius,
                    area,
                    circularity
                )

        return best_detection


def main(args=None):

    rclpy.init(args=args)

    node = OrangeCircleDetector()

    try:

        rclpy.spin(node)

    except KeyboardInterrupt:
        pass

    finally:

        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
