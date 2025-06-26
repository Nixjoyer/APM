#!/bin/bash

CONFIG_DIR="$HOME/.config/APM_v1.0"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_DIR="$HOME/APM_logs"
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# ▶️ Create default config if missing
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOF
# AUR GUI Manager Config
# Packages in this list will NEVER be purged
BLACKLIST=(yay paru trizen base-devel)
EOF
fi

# ▶️ Load config & blacklist
source "$CONFIG_FILE"
BLACKLIST=("${BLACKLIST[@]}")

# ▶️ Sound wrapper
play_sound() {
    canberra-gtk-play --id="$1" --volume=100 2>/dev/null &
}

# ▶️ Check Zenity
if ! command -v zenity >/dev/null 2>&1; then
    echo "Zenity was not found. The GUI is powered by Zenity so please install it with: sudo pacman -S zenity"
    exit 1
fi

# ▶️ Filter out blacklisted packages
filter_blacklist() {
    local all_pkgs=("$@")
    local filtered=()
    for pkg in "${all_pkgs[@]}"; do
        if [[ ! " ${BLACKLIST[*]} " =~ " $pkg " ]]; then
            filtered+=("$pkg")
        fi
    done
    echo "${filtered[@]}"
}

# ▶️ Zenity GUI Options
choose_mode() {
    zenity --list --radiolist \
        --title="APM_v1.0 Mode" \
        --window-icon=software-update-available \
        --column="Select" --column="Mode" \
        TRUE "Dry Run (Selective)" \
        FALSE "Purge Selected Packages" \
        FALSE "Purge All AUR Packages"
}

choose_packages() {
    AUR_PKGS=($(filter_blacklist $(pacman -Qm | awk '{print $1}')))
    if [[ ${#AUR_PKGS[@]} -eq 0 ]]; then
        play_sound dialog-information
        zenity --info --window-icon=dialog-information --text="There no AUR packages available to purge (all are either blacklisted or there are none installed)."
        return 1
    fi

    zenity --list --checklist \
        --title="Select AUR Packages to Purge" \
        --window-icon=software-update-available \
        --column="Select" --column="Package" \
        $(for pkg in "${AUR_PKGS[@]}"; do echo "FALSE $pkg"; done)
}

# ▶️ Main Loop
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
    LOG_FILE="$LOG_DIR/APM_v1.0-$TIMESTAMP.log"

    MODE_CHOICE=$(choose_mode)
    [[ -z "$MODE_CHOICE" ]] && exit 0

    ALL_AUR_PKGS=($(pacman -Qm | awk '{print $1}'))
    FILTERED_PKGS=($(filter_blacklist "${ALL_AUR_PKGS[@]}"))

    if [[ "$MODE_CHOICE" =~ Dry ]]; then
        SELECTED_PKGS_RAW=$(choose_packages) || continue
        [[ -z "$SELECTED_PKGS_RAW" ]] && continue
        IFS="|" read -r -a SELECTED_PKGS <<< "$SELECTED_PKGS_RAW"
        zenity --question \
          --window-icon=help-about \
          --text="Simulate removal for the following packages:\n\n${SELECTED_PKGS[*]}"
        [[ $? -ne 0 ]] && continue
        for pkg in "${SELECTED_PKGS[@]}"; do
            echo "[DRY-RUN] Will remove: $pkg" | tee -a "$LOG_FILE"
        done
        play_sound dialog-information
        zenity --info \
          --window-icon=dialog-information \
          --text="Dry run complete.\n\nLog saved to:\n$LOG_FILE"

    elif [[ "$MODE_CHOICE" =~ Selected ]]; then
        SELECTED_PKGS_RAW=$(choose_packages) || continue
        [[ -z "$SELECTED_PKGS_RAW" ]] && continue
        IFS="|" read -r -a SELECTED_PKGS <<< "$SELECTED_PKGS_RAW"
        zenity --question \
          --window-icon=help-about \
          --text="Purge selected packages:\n\n${SELECTED_PKGS[*]}"
        [[ $? -ne 0 ]] && continue
        for pkg in "${SELECTED_PKGS[@]}"; do
            echo "[REMOVING] $pkg..." | tee -a "$LOG_FILE"
            yay -Rns --noconfirm "$pkg" >> "$LOG_FILE" 2>&1
            if [[ $? -eq 0 ]]; then
                echo "[SUCCESS] Removed: $pkg" | tee -a "$LOG_FILE"
            else
                echo "[FAILED] $pkg" | tee -a "$LOG_FILE"
                play_sound dialog-error
                zenity --error --window-icon=dialog-error --text="Failed to remove $pkg"
            fi
        done
        play_sound complete-copy
        zenity --info \
          --window-icon=emblem-ok \
          --text="Selected packages have been removed.\n\nLog saved to:\n$LOG_FILE"

    elif [[ "$MODE_CHOICE" =~ All ]]; then
        zenity --question \
          --window-icon=dialog-warning \
          --text="Are you sure you want to purge ALL non-blacklisted AUR packages?\n\nThis will remove:\n${FILTERED_PKGS[*]}"
        [[ $? -ne 0 ]] && continue
        for pkg in "${FILTERED_PKGS[@]}"; do
            echo "[REMOVING] $pkg..." | tee -a "$LOG_FILE"
            yay -Rns --noconfirm "$pkg" >> "$LOG_FILE" 2>&1
            if [[ $? -eq 0 ]]; then
                echo "[SUCCESS] Removed: $pkg" | tee -a "$LOG_FILE"
            else
                echo "[FAILED] $pkg" | tee -a "$LOG_FILE"
                play_sound dialog-error
                zenity --error --window-icon=dialog-error --text="Failed to remove $pkg"
            fi
        done
        play_sound complete-copy
        zenity --info \
          --window-icon=emblem-ok \
          --text="All allowed AUR packages have been purged.\n\nLog saved to:\n$LOG_FILE"
    fi

    play_sound dialog-information
    zenity --question \
      --window-icon=help-about \
      --text="Purge complete.\n\nLog saved to:\n$LOG_FILE\n\nDo you want to return to the main menu?"
    [[ $? -ne 0 ]] && break
done

exit 0
