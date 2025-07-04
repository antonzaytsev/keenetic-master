# syntax=docker/dockerfile:1

ARG RUBY_VERSION=3.4.1
ARG DISTRO_NAME=bookworm

FROM ruby:$RUBY_VERSION-slim-$DISTRO_NAME

# Common dependencies
RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
    build-essential \
    gnupg2 \
    curl \
    less \
    git \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3 \
  BUNDLE_PATH=/usr/local/bundle

# Create a directory for the app code
RUN mkdir -p /app
WORKDIR /app

# Copy gemfiles
COPY Gemfile Gemfile.lock ./

# Upgrade RubyGems and install the latest Bundler version
RUN gem update --system && \
    gem install bundler

# Install gems
RUN bundle install

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p tmp/logs tmp/request-dumps config

# Set executable permissions on scripts
RUN chmod +x cmd/*.rb

# Use the crontab script as default command
CMD ["ruby", "cmd/crontab.rb"]
