FROM ubuntu:24.04 AS download

ARG GODOT_VERSION=4.7.2
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip \
	&& rm -rf /var/lib/apt/lists/*
RUN curl --fail --location --retry 3 \
	"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	--output /tmp/godot.zip \
	&& unzip /tmp/godot.zip -d /tmp/godot \
	&& install -m 0755 "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot

FROM ubuntu:24.04

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --uid 10001 --create-home --shell /usr/sbin/nologin godot

COPY --from=download /usr/local/bin/godot /usr/local/bin/godot
WORKDIR /game
COPY --chown=10001:10001 project.godot ./
COPY --chown=10001:10001 assets/ ./assets/
COPY --chown=10001:10001 scenes/ ./scenes/
COPY --chown=10001:10001 scripts/ ./scripts/
COPY --chown=10001:10001 shaders/ ./shaders/

RUN chown 10001:10001 /game
USER 10001:10001
ENV XDG_CACHE_HOME=/tmp/cache
RUN godot --headless --editor --path /game --quit
EXPOSE 27015/udp 27016/udp

ENTRYPOINT ["/bin/bash", "/game/scripts/server_entrypoint.sh"]
CMD ["--server", "--server-port=27015", "--survival"]
