# SPDX-License-Identifier: MulanPSL-2.0
# Runtime image for this deployment: ROS 2 Humble + Robonix Python deps + the
# AUBO Python SDK (the base image already has cv2 and numpy for fruit_pick).
# Build from the repository root:
#   docker build -t robonix-aubo:20260922 -f docker/Dockerfile .
# The base image is the Robonix Webots example image (built by
# examples/webots/sim/start.sh in syswonder/robonix). The SDK wheel is AUBO's
# distribution and is not committed: put it in vendor/ first.
# Robonix binaries are not baked in; the Robonix tree is mounted at
# /opt/robonix and its target/release is on PATH.
FROM robonix_tiago_sim-sim:latest
USER root
RUN python3 -m pip install --no-cache-dir grpcio==1.80.0 grpcio-tools==1.76.0 protobuf==6.33.6
COPY vendor/pyaubo_sdk-0.26.0rc6-cp310-cp310-manylinux2014_x86_64.whl /tmp/
RUN python3 -m pip install --no-deps /tmp/pyaubo_sdk-0.26.0rc6-cp310-cp310-manylinux2014_x86_64.whl && \
    rm /tmp/pyaubo_sdk-0.26.0rc6-cp310-cp310-manylinux2014_x86_64.whl
ENV PATH="/opt/robonix/target/release:${PATH}"
ENV ROBONIX_HOME=/workspace/.runtime/robonix
ENV ROS_DOMAIN_ID=77
ENV ROS_LOCALHOST_ONLY=1
ENV RMW_IMPLEMENTATION=rmw_fastrtps_cpp
ENV ROBONIX_PROVIDER_BIND_HOST=127.0.0.1
ENV ROBONIX_ADVERTISE_HOST=127.0.0.1
WORKDIR /workspace
ENTRYPOINT ["bash", "/workspace/scripts/container-entry.sh"]
