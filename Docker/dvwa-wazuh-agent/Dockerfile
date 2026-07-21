FROM wazuh/wazuh-agent:4.14.6@sha256:4acdfb11b124a7b00420ce335382d5276150f62f410b5958c290019eea13e90e

ARG YARA_VERSION=4.5.5
ARG YARA_SHA256=d38e30fd9c1e1c7921d1c4568262d94f5c2d6b5da139fe49572a43ffbc5c53f6

RUN dnf install -y \
      automake \
      gcc \
      jansson-devel \
      libtool \
      make \
      openssl-devel \
      tar \
    && curl --fail --location --proto '=https' --tlsv1.2 \
      "https://github.com/VirusTotal/yara/archive/refs/tags/v${YARA_VERSION}.tar.gz" \
      --output /tmp/yara.tar.gz \
    && echo "${YARA_SHA256}  /tmp/yara.tar.gz" | sha256sum --check --strict \
    && mkdir /tmp/yara-source \
    && tar --extract --gzip --file /tmp/yara.tar.gz --directory /tmp/yara-source --strip-components=1 \
    && cd /tmp/yara-source \
    && ./bootstrap.sh \
    && ./configure --disable-static \
    && make -j2 \
    && make install \
    && ldconfig \
    && yara --version \
    && dnf remove -y automake gcc jansson-devel libtool make openssl-devel \
    && dnf clean all \
    && rm -rf /var/cache/dnf /tmp/yara-source /tmp/yara.tar.gz

COPY ossec.conf /wazuh-config-mount/etc/ossec.conf
COPY rules/sentinelsoc-test.yar /etc/yara-rules/sentinelsoc-test.yar
COPY active-response/yara-scan.py /var/ossec/active-response/bin/yara-scan.py

RUN chmod 0644 /etc/yara-rules/sentinelsoc-test.yar \
    && chmod 0750 /var/ossec/active-response/bin/yara-scan.py \
    && chown root:wazuh /var/ossec/active-response/bin/yara-scan.py
