#!/bin/bash
set -e
#for install: curl https://raw.githubusercontent.com/trunghieuth10/public/refs/heads/main/telegraf_install.sh|sudo bash

# Detect architecture and return the correct type
detect_arch() {
    . /etc/os-release
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH_TYPE="amd64" ;;
        i386|i686) ARCH_TYPE="i386" ;;
        armv7*) ARCH_TYPE="armhf" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        *) ARCH_TYPE="unknown" ;;
    esac
    echo "$ARCH_TYPE"
}

# Install required tools: jq, netstat
install_dependencies() {
    echo "🔍 Checking required tools..."

    if [[ "$ID" =~ (ubuntu|debian) ]]; then
        if ! command -v jq >/dev/null 2>&1; then
            echo "📦 Installing jq..."
            sudo apt-get install -y jq > /dev/null
        fi
        if ! command -v netstat >/dev/null 2>&1; then
            echo "📦 Installing net-tools (for netstat)..."
            sudo apt-get install -y net-tools > /dev/null
        fi
    elif [[ "$ID" =~ (centos|rhel|rocky|almalinux|fedora|ol) ]]; then
        if ! command -v jq >/dev/null 2>&1; then
            echo "📦 Installing jq..."
            sudo yum install -y jq > /dev/null
        fi
        if ! command -v netstat >/dev/null 2>&1; then
            echo "📦 Installing net-tools (for netstat)..."
            sudo yum install -y net-tools > /dev/null
        fi
    fi
}

# Configure Telegraf repository
config_repository_telegraf() {
    detect_arch
    echo "🔧 Configuring Telegraf repository for $ARCH_TYPE"

    if [[ "$ID" =~ (ubuntu|debian) ]]; then
        wget -q https://repos.influxdata.com/influxdata-archive_compat.key
        echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c
        cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/${ID} stable main" | sudo tee /etc/apt/sources.list.d/influxdata.list
        sudo apt-get update
    elif [[ "$ID" =~ (centos|rhel|rocky|almalinux|fedora|ol) ]]; then
        sudo tee /etc/yum.repos.d/influxdata.repo > /dev/null <<EOF
[influxdata]
name = InfluxData Repository - Stable
baseurl = https://repos.influxdata.com/stable/\$basearch/main
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key
EOF
    else
        echo "❌ Unsupported OS: $ID"
        exit 1
    fi
}

# Install Telegraf
install_telegraf() {
    TELEGRAF_VERSION=$(curl -s https://api.github.com/repos/influxdata/telegraf/releases/latest | jq -r '.tag_name')
    TELEGRAF_BASE_URL="https://dl.influxdata.com/telegraf/releases"
    echo "✅️ Telegraf latest version $TELEGRAF_VERSION"

    if [ -f "/etc/yum.repos.d/influxdata.repo" ] || [ -f "/etc/apt/sources.list.d/influxdata.list" ]; then
        echo "📦 Installing Telegraf from repository"
        if [[ "$ID" =~ (ubuntu|debian) ]]; then
            sudo apt-get install -y telegraf > /dev/null
        else
            sudo yum install -y telegraf > /dev/null
        fi
    else
        detect_arch
        echo "⬇️ Downloading Telegraf $TELEGRAF_VERSION"
        wget "${TELEGRAF_BASE_URL}/telegraf-${TELEGRAF_VERSION}_linux_${ARCH_TYPE}.tar.gz"
        tar xf "telegraf-${TELEGRAF_VERSION}_linux_${ARCH_TYPE}.tar.gz"
        sudo cp "telegraf-${TELEGRAF_VERSION}/usr/bin/telegraf" /usr/local/bin/
    fi
}

# Configure Telegraf Cloud
config_telegraf_cloud() {
    local token="IclOtLROVMfMof3zLJIGqXVzmL_ghvQOVLWGN3psEKI6FCQX3HOvBGQ1AH4I064eDp26o_DVk8UoeG3v9uaUTA=="
    local url="https://us-east-1-1.aws.cloud2.influxdata.com/api/v2/telegrafs/0ec56c3e33489000"
    local service_file="/usr/lib/systemd/system/telegraf.service"

    echo "🔑 Setting INFLUX_TOKEN"
    sudo mkdir -p /etc/default
    echo "INFLUX_TOKEN=$token" | sudo tee /etc/default/telegraf > /dev/null

    if [ -f "$service_file" ]; then
        echo "🔧 Found Telegraf systemd service"

        if grep -q "/etc/telegraf/telegraf.conf" "$service_file"; then
            echo "📝 Replacing config path in ExecStart..."
            sudo sed -i "s|/etc/telegraf/telegraf.conf|$url|g" "$service_file"
            sudo rm -f /etc/telegraf/telegraf.conf
        fi

        sudo mkdir -p /var/log/telegraf
        sudo touch /var/log/telegraf/telegraf.log
        sudo chown telegraf:telegraf -R /var/log/telegraf

        echo "🔁 Reloading systemd..."
        sudo systemctl daemon-reexec
        sudo systemctl daemon-reload

        echo "🟢 Enabling Telegraf service"
        sudo systemctl enable telegraf

        echo "🚀 Restarting Telegraf"
        sudo systemctl restart telegraf

        echo "✅ Telegraf Cloud configuration applied."
    else
        echo "⚠️  $service_file not found."
    fi
}

# Uninstall Telegraf
uninstall_telegraf_cloud() {
    echo "🧼 Uninstalling Telegraf..."
    if systemctl list-unit-files | grep -q telegraf; then
        sudo systemctl disable --now telegraf || true
        sudo systemctl daemon-reload
    fi

    if [[ "$ID" =~ (ubuntu|debian) ]]; then
        sudo apt-get remove --purge -y telegraf || true
    elif [[ "$ID" =~ (centos|rhel|rocky|almalinux|fedora|ol) ]]; then
        sudo yum remove -y telegraf || true
    fi

    for dir in /etc/telegraf /var/lib/telegraf /var/log/telegraf /usr/share/telegraf; do
        if [ -d "$dir" ]; then
            echo "🗑️ Removing $dir"
            sudo rm -rf "$dir"
        fi
    done
}

# Main execution
. /etc/os-release
install_dependencies
uninstall_telegraf_cloud
config_repository_telegraf
install_telegraf
config_telegraf_cloud

# Telegraf process check
echo -e "\n🧪 Checking if Telegraf is running..."
sleep 5
netstat -antp 2>/dev/null | grep telegraf || echo "ℹ️ No Telegraf process found"

# Cleanup script if executed from file
if [ -f "$0" ]; then
    echo "🧹 Removing script file: $0"
    rm -- "$0"
fi
