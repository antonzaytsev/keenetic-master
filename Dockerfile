# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.1
ARG DISTRO_NAME=bookworm

FROM ruby:$RUBY_VERSION-slim-$DISTRO_NAME

RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    build-essential \
    gnupg2 \
    curl \
    less \
    git \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  BUNDLE_PATH=/usr/local/bundle

# Create a directory for the app code
RUN mkdir -p /app
WORKDIR /app

# Create necessary directories
RUN mkdir -p tmp/logs tmp/request-dumps config
