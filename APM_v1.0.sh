#!/bin/bash

# AUR GUI Package Manager with Zenity GUI, KDE sounds, dry-run, selective/full purge, icons & logging

LOG_DIR="$HOME/APM-logs"
mkdir -p "$LOG_DIR"

# Sound wrapper
play_sound() {
    canberra-gtk-play --id="$1" --volume=100 2>/dev/null &
}

# Check Zenity
if ! command -v zenity >/dev/null 2>&1; then
    echo "Zenity not found. The GUI needs Zenity so please install it: sudo pacman -S zenity"
    exit 1
fi

choose_mode() {
    zenity --list --radiolist \
        --title="AUR Purge Mode" \
        --window-icon=software-update-available \
        --column="Select" --column="Mode" \
        TRUE "Dry Run (Selective)" \
        FALSE "Purge Selected Packages" \
        FALSE "Purge All AUR Packages"
}

choose_packages() {
    AUR_PKGS=$(pacman -Qm | awk '{print $1}')
    if [[ -z "$AUR_PKGS" ]]; then
        play_sound dialog-information
        zenity --info --window-icon=dialog-information --text="No AUR packages found!"
        return 1
    fi

    zenity --list --checklist \
        --title="Select AUR Packages to Purge" \
        --window-icon=software-update-available \
        --column="Select" --column="Package" \
        $(while read -r pkg; do echo "FALSE $pkg"; done <<< "$AUR_PKGS")
}

# Main Loop
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
    LOG_FILE="$LOG_DIR/aur-gui-manager-$TIMESTAMP.log"

    MODE_CHOICE=$(choose_mode)
    [[ -z "$MODE_CHOICE" ]] && exit 0

    AUR_PKGS_ARRAY=($(pacman -Qm | awk '{print $1}'))
    if [[ "${#AUR_PKGS_ARRAY[@]}" -eq 0 ]]; then
        play_sound dialog-information
        zenity --info --window-icon=dialog-information --text="No AUR packages installed on the system."
        exit 0
    fi

    if [[ "$MODE_CHOICE" =~ Dry ]]; then
        SELECTED_PKGS_RAW=$(choose_packages) || continue
        [[ -z "$SELECTED_PKGS_RAW" ]] && continue
        IFS="|" read -r -a SELECTED_PKGS <<< "$SELECTED_PKGS_RAW"
        zenity --question \
          --window-icon=help-about \
          --text="Dry run selected for the following packages:\n\n${SELECTED_PKGS[*]}"
        [[ $? -ne 0 ]] && continue
        for pkg in "${SELECTED_PKGS[@]}"; do
            echo "[DRY-RUN] Would remove: $pkg" | tee -a "$LOG_FILE"
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
          --text="Selected packages removed.\n\nLog saved to:\n$LOG_FILE"

    elif [[ "$MODE_CHOICE" =~ All ]]; then
        zenity --question \
          --window-icon=dialog-warning \
          --text="Are you sure you want to purge ALL AUR packages?\n\nThis will remove:\n${AUR_PKGS_ARRAY[*]}"
        [[ $? -ne 0 ]] && continue
        for pkg in "${AUR_PKGS_ARRAY[@]}"; do
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
          --text="All AUR packages purged.\n\nLog saved to:\n$LOG_FILE"
    fi

    # Ask to return to main menu
    play_sound dialog-information
    zenity --question \
      --window-icon=help-about \
      --text="Operation complete.\n\nLog saved to:\n$LOG_FILE\n\nDo you want to return to the main menu?"
    [[ $? -ne 0 ]] && break
done

exit 0
