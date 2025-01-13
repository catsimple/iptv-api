FROM python:3.13 AS builder

ARG LITE=False

WORKDIR /app

COPY Pipfile* ./

RUN pip install pipenv \
  && PIPENV_VENV_IN_PROJECT=1 pipenv install --deploy \
  && if [ "$LITE" = False ]; then pipenv install selenium; fi

RUN apt-get update && apt-get install -y --no-install-recommends wget tar xz-utils

# Determine architecture and download FFmpeg in the same RUN command
ARG TARGETARCH
RUN  mkdir /usr/bin-new \
    && case "$TARGETARCH" in \
        "amd64") ARCH="linux64" ;; \
        "arm64") ARCH="linuxarm64" ;; \
        "arm") ARCH="linuxarm" ;; \
        *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac \
    && wget -O /tmp/ffmpeg.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-${ARCH}-gpl.tar.xz" \
    && tar -xvf /tmp/ffmpeg.tar.xz -C /usr/bin-new/ --strip-components=1 \
    && rm /tmp/ffmpeg.tar.xz

FROM python:3.13-slim

ARG APP_WORKDIR=/iptv-api
ARG LITE=False
ARG APP_PORT=8000

ENV APP_WORKDIR=$APP_WORKDIR
ENV LITE=$LITE
ENV APP_PORT=$APP_PORT
ENV PATH="/.venv/bin:$PATH"

WORKDIR $APP_WORKDIR

COPY . $APP_WORKDIR

COPY --from=builder /app/.venv /.venv

COPY --from=builder /usr/bin-new/* /usr/bin

RUN apt-get update && apt-get install -y --no-install-recommends cron \
  && if [ "$LITE" = False ]; then apt-get install -y --no-install-recommends chromium chromium-driver; fi \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN (crontab -l ; \
  echo "0 22 * * * cd $APP_WORKDIR && /.venv/bin/python main.py"; \
  echo "0 10 * * * cd $APP_WORKDIR && /.venv/bin/python main.py") | crontab -

EXPOSE $APP_PORT

COPY entrypoint.sh /iptv-api-entrypoint.sh

COPY config /iptv-api-config

RUN chmod +x /iptv-api-entrypoint.sh

ENTRYPOINT /iptv-api-entrypoint.sh
