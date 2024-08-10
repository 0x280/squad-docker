#!/bin/bash

# Arguments:
#   $1: app_id
#   $2: installed_manifest_path
should_update() {
    local buildid
    local remote_build_id

    # Extract the buildid from the installed manifest
    buildid=$(grep -Po '"buildid"\s*"\K\d+' "$2")

    # Check if the buildid is valid and non-zero
    if [[ $buildid =~ ^[0-9]+$ ]] && [[ $buildid -ne 0 ]]; then
        echo "[should_update] installed buildid: $buildid"
    else
        echo "[should_update] updating due to invalid installed buildid: $buildid"
        return 1
    fi

    echo "[should_update] fetching remote buildid"

    # Fetch remote buildid using steamcmd
    local output
    output=$(steamcmd \
        +login anonymous \
        +app_info_update 1 \
        +app_info_print "$1" \
        +quit)

    remote_build_id=$(echo "$output" | grep -Po '"branches"\s*{\s*"public"\s*{\s*"buildid"\s*"\K\d+')

    # Check if remote_build_id was successfully extracted
    if [[ -z $remote_build_id ]]; then
        echo "[should_update] failed to fetch remote buildid"
        return 2
    fi

    echo "[should_update] fetched remote buildid: $remote_build_id"

    # Compare the installed buildid with the remote buildid
    if [[ $buildid -eq $remote_build_id ]]; then
        echo "[should_update] installed buildid is up-to-date"
        return 0
    else
        echo "[should_update] installed buildid is out-of-date, updating"
        return 1
    fi
}

install_game() {
    local config_dir="${SQUAD_INSTALL_DIR}/SquadGame/ServerConfig"
    backup_dir="${HOME}/ServerConfig.backup"

    # Check if backup exists and restore it if necessary
    if [ -d "$backup_dir" ]; then
        echo "[install_game] Backup directory already exists. Restoring the backup..."
        if [ -d "$config_dir" ]; then
            echo "[install_game] Removing existing ServerConfig directory before restoring..."
            rm -rf "$config_dir"
        fi
        cp -r "$backup_dir" "$SQUAD_INSTALL_DIR/SquadGame/ServerConfig"
        echo "[install_game] Backup restored successfully."
        return
    fi

    # Backup the existing configuration directory if it exists
    if [ -d "$config_dir" ]; then
        echo "[install_game] Backing up existing ServerConfig directory..."
        cp -r "$config_dir" "$backup_dir"
    fi

    # Install or update the game
    echo "[install_game] Installing or updating the game..."
    bash "steamcmd" +force_install_dir "${SQUAD_INSTALL_DIR}" \
                    +login anonymous \
                    +app_update "${SQUAD_APP_ID}" \
                    +quit

    # Restore the configuration directory from the backup
    if [ -d "$backup_dir" ]; then
        echo "[install_game] Restoring ServerConfig from backup..."
        if [ -d "$config_dir" ]; then
            echo "[install_game] Removing existing ServerConfig directory before restoring..."
            rm -rf "$config_dir"
        fi
        cp -r "$backup_dir" "$SQUAD_INSTALL_DIR/SquadGame/ServerConfig"
        echo "[install_game] Configuration restored successfully."
    else
        echo "[install_game] No backup found, no configuration restored."
    fi
}

# just for good measure
chown ${USER}:${USER} ${SQUAD_INSTALL_DIR}

# check if squad is already installed
if [ -e "${SQUAD_INSTALL_DIR}/steamapps/appmanifest_${SQUAD_APP_ID}.acf" ]; then
    echo "[entry] found Squad appmanifest, checking for update"

    should_update ${SQUAD_APP_ID} "${SQUAD_INSTALL_DIR}/steamapps/appmanifest_${SQUAD_APP_ID}.acf"
    
    if [ $? -eq 1 ]; then
        echo "[entry] update needed, installing..."
        install_game
    else
        echo "[entry] no update needed."
    fi
else
    echo "[entry] Squad appmanifest not found, installing..."

    install_game
fi

# pasted from https://github.com/CM2Walki/Squad/blob/master/bullseye/etc/entry.sh
# Change rcon port on first launch, because the default config overwrites the commandline parameter (you can comment this out if it has done it's purpose)
sed -i -e 's/Port=21114/'"Port=${RCONPORT}"'/g' "${SQUAD_INSTALL_DIR}/SquadGame/ServerConfig/Rcon.cfg"

# TODO:
# check if mods are installed
# if so check their installed build id and update if necessary
# else install them

bash "${SQUAD_INSTALL_DIR}/SquadGameServer.sh" \
			Port="${PORT}" \
			QueryPort="${QUERYPORT}" \
			RCONPORT="${RCONPORT}" \
			beaconport="${beaconport}" \
			FIXEDMAXPLAYERS="${FIXEDMAXPLAYERS}" \
			FIXEDMAXTICKRATE="${FIXEDMAXTICKRATE}" \
			RANDOM="${RANDOM}"
