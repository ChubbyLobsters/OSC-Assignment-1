#!/bin/bash

# ────────────────────────────────────────────────
# Robust User Setup Script for 4-Column CSV
# Author: Cameron
# ────────────────────────────────────────────────

get_csv_file() {
    if [[ -n "$1" ]]; then
        input="$1"
    else
        read -p "Enter CSV file path or URL: " input
    fi

    if [[ "$input" =~ ^https?:// ]]; then
        filename="$(basename "$input")"
        curl -s -o "$filename" "$input" || { echo "❌ Failed to download CSV."; exit 1; }
        input="$filename"
    fi

    [[ -f "$input" ]] || { echo "❌ File not found: $input"; exit 1; }
}

# ─── Generate Unsername from email Function  ──────────────────────────────
generate_username() {
    local email="$1"
    local fullName="${email%@*}"         # Remove domain
    local firstName="${fullName%%.*}"    # First name (before dot)
    local surname="${fullName##*.}"      # Surname (after dot)

    local firstInitial="$(echo "$surname" | cut -c1 | tr '[:upper:]' '[:lower:]')"
    local capFirst="$(echo "${firstName:0:1}" | tr '[:lower:]' '[:upper:]')${firstName:1}"

    echo "${firstInitial}${capFirst}"
}



setup_users() {
    declare -A folderGroups  # Track which groups own which folders

    tail -n +2 "$1" | while IFS=',' read -r email birth groups sharedFolder; do
        # ─── Clean and Normalize Fields ───────────────────────
        email="$(echo "$email" | sed 's/^ *//;s/ *$//;s/^"//;s/"$//')"
        birth="$(echo "$birth" | sed 's/^ *//;s/ *$//;s/^"//;s/"$//')"
        groups="$(echo "$groups" | sed 's/^ *//;s/ *$//;s/^"//;s/"$//')"
        sharedFolder="$(echo "$sharedFolder" | sed 's/^ *//;s/ *$//;s/^"//;s/"$//;s/,$//')"

        # ─── Skip Malformed Rows ──────────────────────────────
        [[ -z "$email" || -z "$birth" ]] && continue

        username="${email%@*}"
        password="$(echo "$birth" | tr -d '/')"

        # ─── Create User If Not Exists ────────────────────────
        if ! id "$username" &>/dev/null; then
            useradd -m "$username"
            echo "$username:$password" | chpasswd
            chage -d 0 "$username"
        fi

        # ─── Assign Groups ────────────────────────────────────
        IFS=',' read -ra groupList <<< "$groups"
        for grp in "${groupList[@]}"; do
            [[ -n "$grp" ]] && getent group "$grp" >/dev/null || groupadd "$grp"
            usermod -aG "$grp" "$username"
        done

        # ─── Setup Shared Folder ──────────────────────────────
        if [[ -n "$sharedFolder" ]]; then
            # Force absolute path
            [[ "$sharedFolder" != /* ]] && sharedFolder="/$sharedFolder"

            # Determine group to own the folder
            folderGroup=""
            for grp in "${groupList[@]}"; do
                if [[ -n "$grp" ]]; then
                    folderGroup="$grp"
                    break
                fi
            done

            # Create folder if not exists
            if [[ ! -d "$sharedFolder" ]]; then
                mkdir -p "$sharedFolder"
                chown root:"$folderGroup" "$sharedFolder"
                chmod 770 "$sharedFolder"
                folderGroups["$sharedFolder"]="$folderGroup"
            else
                # Ensure correct permissions and group ownership
                chown root:"${folderGroups[$sharedFolder]:-$folderGroup}" "$sharedFolder"
                chmod 770 "$sharedFolder"
            fi

            # Add user to folder group
            [[ -n "$folderGroup" ]] && usermod -aG "$folderGroup" "$username"

            # Create symbolic link
            ln -sf "$sharedFolder" "/home/$username/shared"
            chown -h "$username:$username" "/home/$username/shared"
        fi

        # ─── Add Alias for Sudo Users ─────────────────────────
        if [[ "$groups" == *"sudo"* ]]; then
            aliasFile="/home/$username/.bash_aliases"
            if ! grep -q "alias myls=" "$aliasFile" 2>/dev/null; then
                echo "alias myls='ls -la ~'" >> "$aliasFile"
                chown "$username:$username" "$aliasFile"
            fi
        fi
    done
}

main() {
    get_csv_file "$1"
    setup_users "$input"
    echo "✅ All users created, groups assigned, folders linked, and aliases set."
}

main "$@"

