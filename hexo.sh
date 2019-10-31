#!/bin/bash

set -o errexit

hexo clean
hexo g
hexo s
