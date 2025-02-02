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
    less

# Configure bundler
ENV LANG=C.UTF-8 \
  BUNDLE_JOBS=4 \
  BUNDLE_RETRY=3

# Store Bundler settings in the project's root
#ENV BUNDLE_APP_CONFIG=.bundle

# Uncomment this line if you want to run binstubs without prefixing with `bin/` or `bundle exec`
ENV PATH /app/bin:$PATH

# Create a directory for the app code
RUN mkdir -p /app
WORKDIR /app

COPY Gemfile Gemfile.lock /app/

# Upgrade RubyGems and install the latest Bundler version
RUN gem update --system && \
    gem install bundler && \
    bundle

COPY crontab.rb /app/
COPY config /app/config
COPY lib /app/lib

# Use Bash as the default command
CMD ["/bin/bash"]
