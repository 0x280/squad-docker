FROM steamcmd/steamcmd:debian-bookworm

ENV USER=squad
ENV HOME=/home/${USER}

ENV SQUAD_APP_ID=403240
ENV SQUAD_INSTALL_DIR="${HOME}/squad-dedicated"
ENV SQUAD_WORKSHOP_APP_ID=393380
ENV SQUAD_MOD_DIR="${SQUAD_INSTALL_DIR}/SquadGame/Plugins/Mods"
ENV SQUAD_MOD_IDS="()"

RUN groupadd -g 1000 ${USER} \
    && useradd -m -u 1000 -g ${USER} ${USER}

USER ${USER}

COPY --chown=1000:1000 entry.sh ${HOME}

RUN set -x \
    && mkdir -p "${SQUAD_INSTALL_DIR}" \
    && chmod 755 "${HOME}/entry.sh" "${SQUAD_INSTALL_DIR}" \
    && chown -R "${USER}:${USER}" "${HOME}"

WORKDIR ${HOME}

ENV PORT=7787 \
	QUERYPORT=27165 \
	RCONPORT=21114 \
    beaconport=15000 \
	FIXEDMAXPLAYERS=100 \
	FIXEDMAXTICKRATE=50 \
	RANDOM=NONE

EXPOSE 7787/udp \
	27165/tcp \
	27165/udp \
	21114/tcp \
	21114/udp \
    15000/tcp \
    15000/udp

CMD ["entry.sh"]
ENTRYPOINT [ "bash" ]
