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

    echo "[should_update] fetching remote buildid..."

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

setup_mod_symlinks() {
    local mods_dir="${SQUAD_INSTALL_DIR}/steamapps/workshop/content/${SQUAD_WORKSHOP_APP_ID}"
    local target_dir="${SQUAD_INSTALL_DIR}/SquadGame/Plugins/Mods"

    for symlink in "${target_dir}"/*; do
        # Check if it's a symlink
        if [ -L "$symlink" ]; then
            # Get the actual path the symlink points to
            linked_target=$(readlink "$symlink")

            # Check if it points to a folder inside mods_dir
            if [[ "$linked_target" == "${mods_dir}"/* ]]; then
                echo "[setup_mod_symlinks] Removing symlink: $symlink"
                rm "$symlink"
            fi
        fi
    done

    # Create new symlinks from mods_dir to target_dir
    for mod_folder in "${mods_dir}"/*; do
        if [ -d "$mod_folder" ]; then
            mod_name=$(basename "$mod_folder")
            target_symlink="${target_dir}/${mod_name}"

            echo "[setup_mod_symlinks] Creating symlink for $mod_folder at $target_symlink"
            ln -s "$mod_folder" "$target_symlink"
        fi
    done
}

# Arguments:
#   $1: mod_ids
install_mods() {
    for mod_id in $1; do
        # Install or update the mod
        echo "[install_mods:$mod_id] Installing the mod..."
        bash "steamcmd" +force_install_dir "${SQUAD_INSTALL_DIR}" \
            +login anonymous \
            +workshop_download_item "${SQUAD_WORKSHOP_APP_ID}" $mod_id \
            +quit
        echo "[install_mods:$mod_id] Success"
    done

    setup_mod_symlinks
}

# Arguments:
#   $1: mod_ids
fix_windows_only_mods() {
    local mods_dir="${SQUAD_INSTALL_DIR}/steamapps/workshop/content/${SQUAD_WORKSHOP_APP_ID}"

    for mod_id in $1; do
        pak_dir=$(find "$mods_dir/$mod_id" -type d -path "*/Content/Paks" -print -quit)

        if [ -z "$pak_dir" ]; then
            echo "[fix_windows_only_mods:$mod_id] Couldn't find Content/Paks dir for windows mod"
        else
            echo "[fix_windows_only_mods:$mod_id] Found the following Content/Paks directory: $pak_dir"

            windows_dir="$pak_dir/WindowsNoEditor"
            linux_dir="$pak_dir/LinuxServer"

            if [ -d "$windows_dir" ]; then
                if [ -d "$linux_dir" ]; then
                    rm -rf $linux_dir
                fi

                mv $windows_dir $linux_dir

                echo "[fix_windows_only_mods:$mod_id] patched successfully"
            fi
        fi
    done
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

MOD_IDS=$(echo "${SQUAD_MOD_IDS}" | tr -d '()"\"' | tr ',' ' ')
install_mods $MOD_IDS

WINDOWS_ONLY_MOD_IDS=$(echo "${SQUAD_WINDOWS_ONLY_MOD_IDS}" | tr -d '()"\"' | tr ',' ' ')
install_mods $WINDOWS_ONLY_MOD_IDS
fix_windows_only_mods $WINDOWS_ONLY_MOD_IDS

bash "${SQUAD_INSTALL_DIR}/SquadGameServer.sh" \
    Port="${PORT}" \
    QueryPort="${QUERYPORT}" \
    RCONPORT="${RCONPORT}" \
    beaconport="${beaconport}" \
    FIXEDMAXPLAYERS="${FIXEDMAXPLAYERS}" \
    FIXEDMAXTICKRATE="${FIXEDMAXTICKRATE}" \
    RANDOM="${RANDOM}"
