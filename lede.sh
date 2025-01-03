#!/usr/bin/env bash

if [[ $REBUILD_TOOLCHAIN = 'true' ]]; then
    echo -e "\e[1;33m开始打包toolchain目录\e[0m"
    cd $OPENWRT_PATH
    sed -i 's/ $(tool.*\/stamp-compile)//' Makefile
    [ -d ".ccache" ] && (ccache=".ccache"; ls -alh .ccache)
    du -h --max-depth=1 ./staging_dir
    du -h --max-depth=1 ./ --exclude=staging_dir
    tar -I zstdmt -cf $GITHUB_WORKSPACE/output/$CACHE_NAME.tzst staging_dir/host* staging_dir/tool* $ccache
    if [[ $(du -sm $GITHUB_WORKSPACE/output | cut -f1) -ge 150 ]]; then
        ls -lh $GITHUB_WORKSPACE/output
        echo "OUTPUT_RELEASE=true" >>$GITHUB_ENV
    fi
    exit 0
fi

[ -d $GITHUB_WORKSPACE/output ] || mkdir $GITHUB_WORKSPACE/output

color() {
    case $1 in
        cr) echo -e "\e[1;31m$2\e[0m" ;;
        cg) echo -e "\e[1;32m$2\e[0m" ;;
        cy) echo -e "\e[1;33m$2\e[0m" ;;
        cb) echo -e "\e[1;34m$2\e[0m" ;;
        cp) echo -e "\e[1;35m$2\e[0m" ;;
        cc) echo -e "\e[1;36m$2\e[0m" ;;
    esac
}

status() {
    local check=$? end_time=$(date '+%H:%M:%S') total_time
    total_time="==> 用时 $[$(date +%s -d $end_time) - $(date +%s -d $begin_time)] 秒"
    [[ $total_time =~ [0-9]+ ]] || total_time=""
    if [[ $check = 0 ]]; then
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $step_name) [ $(color cg ✔) ] $(echo -e "\e[1m$total_time")
    else
        printf "%-62s %s %s %s %s %s %s %s\n" \
        $(color cy $step_name) [ $(color cr ✕) ] $(echo -e "\e[1m$total_time")
    fi
}

find_dir() {
    find $1 -maxdepth 3 -type d -name $2 -print -quit 2>/dev/null
}

add_package() {
    local z
    for z in $@; do
        [[ $z =~ ^# ]] || echo "CONFIG_PACKAGE_$z=y" >>.config
    done
}

del_package() {
    local z
    for z in $@; do
        [[ $z =~ ^# ]] || sed -i -E "s/(CONFIG_PACKAGE_.*$z)=y/# \1 is not set/" .config
    done
}

print_info() {
    read -r param1 param2 param3 param4 param5 <<< $1
    printf "%s %-40s %s %s %s\n" $param1 $param2 $param3 $param4 $param5
}

git_clone() {
    local repo_url branch
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    local target_dir current_dir destination_dir
    if [[ -n "$@" ]]; then
        target_dir="$@"
    else
        target_dir="${repo_url##*/}"
    fi
    if ! git clone -q $branch --depth=1 $repo_url $target_dir 2>/dev/null; then
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    fi
    rm -rf $target_dir/{.git*,README*.md,LICENSE}
    current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
    if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
        mv -f $target_dir ${current_dir%/*}
        print_info "$(color cg 替换) $target_dir [ $(color cg ✔) ]"
    else
        destination_dir="package/A"
        [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
        mv -f $target_dir $destination_dir
        print_info "$(color cb 添加) $target_dir [ $(color cb ✔) ]"
    fi
}

clone_dir() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    if ! git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null; then
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    fi
    local target_dir source_dir current_dir destination_dir
    for target_dir in "$@"; do
        [[ $target_dir =~ ^# ]] && continue
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        [[ -d "$source_dir" ]] || \
        source_dir=$(find "$temp_dir" -maxdepth 4 -type d -name "$target_dir" -print -quit) && \
        [[ -d "$source_dir" ]] || {
            print_info "$(color cr 查找) $target_dir [ $(color cr ✕) ]"
            continue
        }
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info "$(color cg 替换) $target_dir [ $(color cg ✔) ]"
        else
            destination_dir="package/A"
            [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
            mv -f $source_dir $destination_dir
            print_info "$(color cb 添加) $target_dir [ $(color cb ✔) ]"
        fi
    done
    rm -rf $temp_dir
}

clone_all() {
    local repo_url branch temp_dir=$(mktemp -d)
    if [[ "$1" == */* ]]; then
        repo_url="$1"
        shift
    else
        branch="-b $1 --single-branch"
        repo_url="$2"
        shift 2
    fi
    if ! git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null; then
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    fi
    local target_dir source_dir current_dir destination_dir
    for target_dir in $(ls -l $temp_dir/$@ | awk '/^d/{print $NF}'); do
        source_dir=$(find_dir "$temp_dir" "$target_dir")
        current_dir=$(find_dir "package/ feeds/ target/" "$target_dir")
        if ([[ -d "$current_dir" ]] && rm -rf $current_dir); then
            mv -f $source_dir ${current_dir%/*}
            print_info "$(color cg 替换) $target_dir [ $(color cg ✔) ]"
        else
            destination_dir="package/A"
            [[ -d "$destination_dir" ]] || mkdir -p $destination_dir
            mv -f $source_dir $destination_dir
            print_info "$(color cb 添加) $target_dir [ $(color cb ✔) ]"
        fi
    done
    rm -rf $temp_dir
}

config() {
	case "$TARGET_DEVICE" in
		"x86_64")
			cat >.config<<-EOF
			CONFIG_TARGET_x86=y
			CONFIG_TARGET_x86_64=y
			CONFIG_TARGET_x86_64_DEVICE_generic=y
			CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
			CONFIG_BUILD_NLS=y
			CONFIG_BUILD_PATENTED=y
			CONFIG_TARGET_IMAGES_GZIP=y
			CONFIG_GRUB_IMAGES=y
			# CONFIG_GRUB_EFI_IMAGES is not set
			# CONFIG_VMDK_IMAGES is not set
			EOF
			KERNEL_TARGET=amd64
			;;
		"r1-plus-lts"|"r1-plus"|"r4s"|"r2c"|"r2s")
			cat >.config<<-EOF
			CONFIG_TARGET_rockchip=y
			CONFIG_TARGET_rockchip_armv8=y
			CONFIG_TARGET_ROOTFS_PARTSIZE=$PART_SIZE
			CONFIG_BUILD_NLS=y
			CONFIG_BUILD_PATENTED=y
			CONFIG_DRIVER_11AC_SUPPORT=y
			CONFIG_DRIVER_11N_SUPPORT=y
			CONFIG_DRIVER_11W_SUPPORT=y
			EOF
			case "$TARGET_DEVICE" in
			"r1-plus-lts"|"r1-plus")
			echo "CONFIG_TARGET_rockchip_armv8_DEVICE_xunlong_orangepi-$TARGET_DEVICE=y" >>.config ;;
			"r4s"|"r2c"|"r2s")
			echo "CONFIG_TARGET_rockchip_armv8_DEVICE_friendlyarm_nanopi-$TARGET_DEVICE=y" >>.config ;;
			esac
			KERNEL_TARGET=arm64
			;;
		"newifi-d2")
			cat >.config<<-EOF
			CONFIG_TARGET_ramips=y
			CONFIG_TARGET_ramips_mt7621=y
			CONFIG_TARGET_ramips_mt7621_DEVICE_d-team_newifi-d2=y
			EOF
			;;
		"phicomm_k2p")
			cat >.config<<-EOF
			CONFIG_TARGET_ramips=y
			CONFIG_TARGET_ramips_mt7621=y
			CONFIG_TARGET_ramips_mt7621_DEVICE_phicomm_k2p=y
			EOF
			;;
		"asus_rt-n16")
			cat >.config<<-EOF
			CONFIG_TARGET_bcm47xx=y
			CONFIG_TARGET_bcm47xx_mips74k=y
			CONFIG_TARGET_bcm47xx_mips74k_DEVICE_asus_rt-n16=y
			EOF
			;;
		"armvirt-64")
			cat >.config<<-EOF
			CONFIG_TARGET_armvirt=y
			CONFIG_TARGET_armvirt_64=y
			CONFIG_TARGET_armvirt_64_DEVICE_generic=y
			EOF
			KERNEL_TARGET=arm64
			;;
	esac
}

REPO_URL="https://github.com/coolsnowwolf/lede"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
step_name='拉取编译源码'; begin_time=$(date '+%H:%M:%S')
#cd /workdir
git clone -q $REPO_URL openwrt
status
#ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[[ -d openwrt ]] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV

[[ $REPO_BRANCH =~ 18.06|master ]] && sed -i '/luci/s/^#//; /openwrt-23.05/s/^/#/' feeds.conf.default

step_name='生成全局变量'; begin_time=$(date '+%H:%M:%S')
config
make defconfig 1>/dev/null 2>&1

SOURCE_REPO=$(basename $REPO_URL)
echo "SOURCE_REPO=$SOURCE_REPO" >>$GITHUB_ENV
echo "LITE_BRANCH=${REPO_BRANCH#*-}" >>$GITHUB_ENV

TARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_BOARD/{print $2}' .config)
SUBTARGET_NAME=$(awk -F '"' '/CONFIG_TARGET_SUBTARGET/{print $2}' .config)
DEVICE_TARGET=$TARGET_NAME-$SUBTARGET_NAME
echo "DEVICE_TARGET=$DEVICE_TARGET" >>$GITHUB_ENV

KERNEL=$(grep -oP 'KERNEL_PATCHVER:=\K[^ ]+' target/linux/$TARGET_NAME/Makefile)
KERNEL_VERSION=$(awk -F '-' '/KERNEL/{print $2}' include/kernel-$KERNEL | awk '{print $1}')
echo "KERNEL_VERSION=$KERNEL_VERSION" >>$GITHUB_ENV

TOOLS_HASH=$(git log --pretty=tformat:"%h" -n1 tools toolchain)
CACHE_NAME="$SOURCE_REPO-master-$DEVICE_TARGET-cache-$TOOLS_HASH"
echo "CACHE_NAME=$CACHE_NAME" >>$GITHUB_ENV
status

# CACHE_URL=$(curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | awk -F '"' '/download_url/{print $4}' | grep $CACHE_NAME)
curl -sL api.github.com/repos/$GITHUB_REPOSITORY/releases | grep -oP 'download_url": "\K[^"]*cache[^"]*' >xa
curl -sL api.github.com/repos/haiibo/toolchain-cache/releases | grep -oP 'download_url": "\K[^"]*cache[^"]*' >xc
if (grep -q $CACHE_NAME xa || grep -q $CACHE_NAME xc); then
    step_name='下载toolchain缓存文件'; begin_time=$(date '+%H:%M:%S')
    grep -q $CACHE_NAME xa && wget -qc -t=3 $(grep $CACHE_NAME xa) || wget -qc -t=3 $(grep $CACHE_NAME xc)
    [ -e *.tzst ]; status
    [ -e *.tzst ] && {
        step_name='部署toolchain编译工具'; begin_time=$(date '+%H:%M:%S')
        tar -I unzstd -xf *.tzst || tar -xf *.tzst
        grep -q $CACHE_NAME xa || (cp *.tzst $GITHUB_WORKSPACE/output && echo "OUTPUT_RELEASE=true" >>$GITHUB_ENV)
        sed -i 's/ $(tool.*\/stamp-compile)//' Makefile && rm xa xc
        [ -d staging_dir ]; status
    }
else
    echo "REBUILD_TOOLCHAIN=true" >>$GITHUB_ENV
fi

step_name='更新&安装插件'; begin_time=$(date '+%H:%M:%S')
./scripts/feeds update -a 1>/dev/null 2>&1
./scripts/feeds install -a 1>/dev/null 2>&1
status

color cy "添加&替换插件"
clone_all https://github.com/hong0980/build
clone_all https://github.com/fw876/helloworld
clone_all https://github.com/xiaorouji/openwrt-passwall-packages
clone_all https://github.com/xiaorouji/openwrt-passwall
clone_all https://github.com/xiaorouji/openwrt-passwall2
clone_dir https://github.com/vernesong/OpenClash luci-app-openclash
# clone_dir https://github.com/sbwml/openwrt_helloworld xray-core v2ray-core v2ray-geodata sing-box

[[ "$REPO_BRANCH" =~ 18.06|master ]] && {
    clone_all v5-lua https://github.com/sbwml/luci-app-mosdns
    clone_all lua https://github.com/sbwml/luci-app-alist
    git_clone 18.06 https://github.com/kiddin9/luci-theme-edge
    git_clone 18.06 https://github.com/jerrykuku/luci-theme-argon
    git_clone 18.06 https://github.com/jerrykuku/luci-app-argon-config
    git_clone https://github.com/kongfl888/luci-app-adguardhome
    clone_all https://github.com/sirpdboy/luci-app-ddns-go
    git_clone https://github.com/ximiTech/luci-app-msd_lite
    git_clone https://github.com/ximiTech/msd_lite
    clone_dir https://github.com/xiaoqingfengATGH/luci-theme-infinityfreedom luci-theme-infinityfreedom-ng
    clone_dir https://github.com/haiibo/packages luci-theme-opentomcat
}

[[ ! "$REPO_BRANCH" =~ 18.06|master ]] && {
    clone_all https://github.com/sbwml/luci-app-mosdns
    clone_all https://github.com/sbwml/luci-app-alist
    git_clone https://github.com/kiddin9/luci-theme-edge
    git_clone https://github.com/jerrykuku/luci-theme-argon
    git_clone https://github.com/jerrykuku/luci-app-argon-config
}

[ "$TARGET_DEVICE" != phicomm_k2p -a "$TARGET_DEVICE" != newifi-d2 ] && {
    git_clone https://github.com/sbwml/packages_lang_golang golang
    git_clone https://github.com/zzsj0928/luci-app-pushbot
    git_clone https://github.com/ilxp/luci-app-ikoolproxy
    clone_all https://github.com/destan19/OpenAppFilter
    clone_dir https://github.com/sirpdboy/luci-app-cupsd luci-app-cupsd cups
    clone_dir https://github.com/kiddin9/kwrt-packages luci-app-bypass lua-neturl cpulimit
    clone_all https://github.com/brvphoenix/wrtbwmon
    clone_all https://github.com/linkease/istore luci
    git_clone master https://github.com/UnblockNeteaseMusic/luci-app-unblockneteasemusic
    sed -i '/log_check/s/^/#/' $(find_dir "package/ feeds/" "luci-app-unblockneteasemusic")/root/etc/init.d/unblockneteasemusic
}

[[ "$TARGET_DEVICE" =~ armvirt-64 ]] && clone_all https://github.com/ophub/luci-app-amlogic

step_name='加载个人设置'; begin_time=$(date '+%H:%M:%S')

config

cat >>.config <<-EOF
	CONFIG_KERNEL_BUILD_USER="buy404"
	CONFIG_KERNEL_BUILD_DOMAIN="OpenWrt"
	CONFIG_PACKAGE_automount=y
	CONFIG_PACKAGE_autosamba=y
	CONFIG_PACKAGE_luci-app-accesscontrol=y
	CONFIG_PACKAGE_luci-app-bridge=y
	CONFIG_PACKAGE_luci-app-cowb-speedlimit=y
	CONFIG_PACKAGE_luci-app-cowbping=y
	CONFIG_PACKAGE_luci-app-cpulimit=y
	CONFIG_PACKAGE_luci-app-ddnsto=y
	CONFIG_PACKAGE_luci-app-filebrowser=y
	CONFIG_PACKAGE_luci-app-filetransfer=y
	CONFIG_PACKAGE_luci-app-network-settings=y
	CONFIG_PACKAGE_luci-app-oaf=y
	CONFIG_PACKAGE_luci-app-passwall=y
	CONFIG_PACKAGE_luci-app-timedtask=y
	CONFIG_PACKAGE_luci-app-ssr-plus=y
	CONFIG_PACKAGE_luci-app-wrtbwmon=y
	CONFIG_PACKAGE_luci-app-ttyd=y
	CONFIG_PACKAGE_luci-app-upnp=y
	CONFIG_PACKAGE_luci-app-ikoolproxy=y
	CONFIG_PACKAGE_luci-app-simplenetwork=y
	CONFIG_PACKAGE_luci-app-opkg=y
	CONFIG_PACKAGE_luci-app-diskman=y
	CONFIG_PACKAGE_luci-app-syncdial=y
	CONFIG_PACKAGE_luci-theme-bootstrap=y
	CONFIG_PACKAGE_luci-app-tinynote=y
	CONFIG_PACKAGE_luci-app-arpbind=y
	CONFIG_PACKAGE_luci-app-wifischedule=y
	# CONFIG_PACKAGE_luci-app-unblockmusic is not set
	# CONFIG_PACKAGE_luci-app-wireguard is not set
	# CONFIG_PACKAGE_luci-app-autoreboot is not set
	# CONFIG_PACKAGE_luci-app-ddns is not set
	# CONFIG_PACKAGE_luci-app-ssr-plus is not set
	# CONFIG_PACKAGE_luci-app-zerotier is not set
	# CONFIG_PACKAGE_luci-app-ipsec-vpnd is not set
	# CONFIG_PACKAGE_luci-app-xlnetacc is not set
	# CONFIG_PACKAGE_luci-app-uugamebooster is not set
EOF

[[ ! "$REPO_BRANCH" =~ 18.06|master ]] && {
    add_package "
    luci-app-wizard
    luci-app-log-OpenWrt-19.07
    "
}

[[ $REPO_URL =~ "coolsnowwolf" ]] && {
    # sed -i "/DISTRIB_DESCRIPTION/ {s/'$/-$SOURCE_REPO-$(date +%Y年%m月%d日)'/}" package/*/*/*/openwrt_release
    sed -i "/VERSION_NUMBER/ s/if.*/if \$(VERSION_NUMBER),\$(VERSION_NUMBER),${REPO_BRANCH#*-}-SNAPSHOT)/" include/version.mk
    sed -i 's/option enabled.*/option enabled 1/' feeds/*/*/*/*/upnpd.config
    sed -i "/listen_https/ {s/^/#/g}" package/*/*/*/files/uhttpd.config
    sed -i 's/UTC/UTC-8/' Makefile
    sed -i "{
            /upnp/d;/banner/d;/openwrt_release/d;/shadow/d
            s|zh_cn|zh_cn\nuci set luci.main.mediaurlbase=/luci-static/bootstrap|
            \$i sed -i 's/root::.*/root:\$1\$V4UetPzk\$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' /etc/shadow\n[ -f '/bin/bash' ] && sed -i '/\\\/ash$/s/ash/bash/' /etc/passwd
            }" $(find package/ -type f -name "*default-settings" 2>/dev/null)
}

[ "$TARGET_DEVICE" != phicomm_k2p -a "$TARGET_DEVICE" != newifi-d2 ] && {
    add_package "
    luci-app-aria2
    luci-app-cifs-mount
    luci-app-commands
    luci-app-hd-idle
    luci-app-pushbot
    luci-app-eqos
    luci-app-softwarecenter
    luci-app-transmission
    luci-app-usb-printer
    luci-app-vssr
    luci-app-bypass
    luci-app-cupsd
    luci-app-adguardhome
    luci-app-openclash
    luci-app-weburl
    luci-app-wol
    luci-app-zerotier
    luci-app-argon-config
    luci-theme-argon
    axel patch diffutils collectd-mod-ping collectd-mod-thermal wpad-wolfssl
    "
    for d in $(find feeds/ package/ -type f -name "index.htm" 2>/dev/null); do
        if grep -q "Kernel Version" $d; then
            sed -i 's|os.date(.*|os.date("%F %X") .. " " .. translate(os.date("%A")),|' $d
            sed -i '/<%+footer%>/i<%-\n\tlocal incdir = util.libpath() .. "/view/admin_status/index/"\n\tif fs.access(incdir) then\n\t\tlocal inc\n\t\tfor inc in fs.dir(incdir) do\n\t\t\tif inc:match("%.htm$") then\n\t\t\t\tinclude("admin_status/index/" .. inc:gsub("%.htm$", ""))\n\t\t\tend\n\t\tend\n\t\end\n-%>\n' $d
            sed -i 's| <%=luci.sys.exec("cat /etc/bench.log") or ""%>||' $d
        fi
    done
    sed -i 's/ariang/ariang +webui-aria2/g' feeds/*/*/luci-app-aria2/Makefile
}

echo -e '\nwww.nicept.net' | tee -a $(find package/A/luci-* feeds/luci/applications/luci-* -type f -name "black.list" -o -name "proxy_host" 2>/dev/null | grep "ss") >/dev/null

mwan3=feeds/packages/net/mwan3/files/etc/config/mwan3
[[ -f $mwan3 ]] && grep -q "8.8" $mwan3 && sed -i '/8.8/d' $mwan3

# echo '<iframe src="https://ip.skk.moe/simple" style="width: 100%; border: 0"></iframe>' | \
# tee -a {$(find_dir "package/ feeds/" "luci-app-vssr")/*/*/*/status_top.htm,$(find_dir "package/ feeds/" "luci-app-ssr-plus")/*/*/*/status.htm,$(find_dir "package/ feeds/" "luci-app-bypass")/*/*/*/status.htm,$(find_dir "package/ feeds/" "luci-app-passwall")/*/*/*/global/status.htm} >/dev/null
xb=$(find_dir "package/ feeds/" "luci-app-bypass")
[[ -d $xb ]] && sed -i 's/default y/default n/g' $xb/Makefile
qBittorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*-\K\d+\.\d+\.\d+')
libtorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*v\K\d+\.\d+\.\d+')
xc=$(find_dir "package/ feeds/" "qBittorrent-static")
[[ -d $xc ]] && [[ $qBittorrent_version ]] && sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${qBittorrent_version:-4.6.5}_v${libtorrent_version:-2.0.10}/" $xc/Makefile
xd=$(find_dir "package/ feeds/" "luci-app-turboacc")
[[ -d $xd ]] && sed -i '/hw_flow/s/1/0/;/sfe_flow/s/1/0/;/sfe_bridge/s/1/0/' $xd/root/etc/config/turboacc
xe=$(find_dir "package/ feeds/" "luci-app-ikoolproxy")
[[ -d $xe ]] && sed -i '/echo .*root/ s/echo /[ $time =~ [0-9]+ ] \&\& echo /' $xe/root/etc/init.d/koolproxy
xg=$(find_dir "package/ feeds/" "luci-app-pushbot")
[[ -d $xg ]] && {
    sed -i "s|-c pushbot|/usr/bin/pushbot/pushbot|" $xg/luasrc/controller/pushbot.lua
    sed -i '/start()/a[ "$(uci get pushbot.@pushbot[0].pushbot_enable)" -eq "0" ] && return 0' $xg/root/etc/init.d/pushbot
}

trv=$(awk -F= '/PKG_VERSION:/{print $2}' feeds/packages/net/transmission/Makefile)
[[ $trv ]] && wget -qO feeds/packages/net/transmission/patches/tr$trv.patch \
raw.githubusercontent.com/hong0980/diy/master/files/transmission/tr$trv.patch 1>/dev/null 2>&1

cat <<-\EOF >feeds/packages/lang/python/python3/files/python3-package-uuid.mk
define Package/python3-uuid
$(call Package/python3/Default)
TITLE:=Python $(PYTHON3_VERSION) UUID module
DEPENDS:=+python3-light +libuuid
endef

$(eval $(call Py3BasePackage,python3-uuid, \
/usr/lib/python$(PYTHON3_VERSION)/uuid.py \
/usr/lib/python$(PYTHON3_VERSION)/lib-dynload/_uuid.$(PYTHON3_SO_SUFFIX) \
))
EOF

config_generate="package/base-files/files/bin/config_generate"
wget -qO package/base-files/files/etc/banner git.io/JoNK8

case "$TARGET_DEVICE" in
    "x86_64")
        FIRMWARE_TYPE="squashfs-combined"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "
        luci-app-adbyby-plus
        #luci-app-amule
        luci-app-deluge
        luci-app-passwall2
        luci-app-dockerman
        luci-app-netdata
        #luci-app-kodexplorer
        luci-app-poweroff
        luci-app-qbittorrent
        luci-app-smartdns
        #luci-app-unblockmusic
        #luci-app-aliyundrive-fuse
        #luci-app-aliyundrive-webdav
        #AmuleWebUI-Reloaded ariang bash htop lscpu lsscsi lsusb nano pciutils screen webui-aria2 zstd tar pv
        #subversion-client #unixodbc #git-http
        "
        sed -i '/easymesh/d' .config
        rm -rf package/lean/rblibtorrent
        # sed -i '/KERNEL_PATCHVER/s/=.*/=6.1/' target/linux/x86/Makefile
        wget -qO package/lean/autocore/files/x86/index.htm \
        https://raw.githubusercontent.com/immortalwrt/luci/openwrt-18.06-k5.4/modules/luci-mod-admin-full/luasrc/view/admin_status/index.htm
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        ;;
    "r1-plus-lts"|"r4s"|"r2c"|"r2s")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "
        luci-app-cpufreq
        luci-app-adbyby-plus
        luci-app-dockerman
        luci-app-qbittorrent
        luci-app-turboacc
        luci-app-passwall2
        #luci-app-easymesh
        luci-app-store
        #luci-app-unblockneteasemusic
        #luci-app-amule
        #luci-app-smartdns
        #luci-app-aliyundrive-fuse
        #luci-app-aliyundrive-webdav
        luci-app-deluge
        luci-app-netdata
        htop lscpu lsscsi lsusb #nano pciutils screen zstd pv
        #AmuleWebUI-Reloaded #subversion-client unixodbc #git-http
        "
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        sed -i "/interfaces_lan_wan/s/'eth1' 'eth0'/'eth0' 'eth1'/" target/linux/rockchip/*/*/*/*/02_network
        ;;
    "armvirt-64")
        FIRMWARE_TYPE="generic-rootfs"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "
        attr bash blkid brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio
        btrfs-progs cfdisk chattr curl dosfstools e2fsprogs f2fs-tools f2fsck fdisk getopt
        hostpad-common htop install-program iperf3 kmod-brcmfmac kmod-brcmutil kmod-cfg80211
        kmod-fs-exfat kmod-fs-ext4 kmod-fs-vfat kmod-mac80211 kmod-rt2800-usb kmod-usb-net
        kmod-usb-net-asix-ax88179 kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 kmod-usb-storage
        kmod-usb-storage-extras kmod-usb-storage-uas kmod-usb2 kmod-usb3 lm-sensors losetup
        lsattr lsblk lscpu lsscsi mkf2fs ntfs-3g parted pv python3 resize2fs tune2fs unzip
        uuidgen wpa-cli wpad wpad-basic xfs-fsck xfs-mkf
        luci-app-adguardhome
        luci-app-cpufreq
        luci-app-dockerman
        luci-app-qbittorrent
        "
        sed -i '/easymesh/d' .config
        # wget -qO feeds/luci/applications/luci-app-qbittorrent/Makefile https://raw.githubusercontent.com/immortalwrt/luci/openwrt-18.06/applications/luci-app-qbittorrent/Makefile
        # sed -i 's/-Enhanced-Edition//' feeds/luci/applications/luci-app-qbittorrent/Makefile
        sed -i 's/arm/arm||TARGET_armvirt_64/g' $(find_dir "package/ feeds/" "luci-app-cpufreq")/Makefile
        sed -i "s/default 160/default $PART_SIZE/" config/Config-images.in
        sed -i 's/services/system/; s/00//' $(find_dir "package/ feeds/" "luci-app-cpufreq")/luasrc/controller/cpufreq.lua
        [ -d ../opt/openwrt_packit ] && {
        sed -i '{
        s|mv |mv -v |
        s|openwrt-armvirt-64-default-rootfs.tar.gz|$(ls *default-rootfs.tar.gz)|
        s|TGT_IMG=.*|TGT_IMG="${WORK_DIR}/unifreq-openwrt-${SOC}_${BOARD}_k${KERNEL_VERSION}${SUBVER}-$(date "+%Y-%m%d-%H%M").img"|
        }' ../opt/openwrt_packit/mk*.sh
        sed -i '/ KERNEL_VERSION.*flippy/ {s/KERNEL_VERSION.*/KERNEL_VERSION="5.15.4-flippy-67+"/}' ../opt/openwrt_packit/make.env
        }
        ;;
    "newifi-d2")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "luci-app-easymesh"
        del_package "ikoolproxy openclash transmission softwarecenter aria2 vssr adguardhome"
        ;;
    "phicomm_k2p")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "luci-app-easymesh"
        del_package "samba4 luci-app-usb-printer luci-app-cifs-mount diskman cupsd autosamba automount"
        ;;
    "asus_rt-n16")
        FIRMWARE_TYPE="n16"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
esac

sed -i '/config PACKAGE_\$(PKG_NAME)_INCLUDE_SingBox/,$ { /default y/ { s/default y/default n/; :loop; n; b loop } }' $(find_dir "package/ feeds/" "luci-app-passwall")/Makefile
sed -i '/bridged/d; /deluge/d; /transmission/d' .config

sed -i \
    -e 's?\.\./\.\./luci.mk?$(TOPDIR)/feeds/luci/luci.mk?' \
    -e 's?include \.\./\.\./\(lang\|devel\)?include $(TOPDIR)/feeds/packages/\1?' \
    -e 's/\(\(^\| \|    \)\(PKG_HASH\|PKG_MD5SUM\|PKG_MIRROR_HASH\|HASH\):=\).*/\1skip/' \
package/A/*/Makefile 2>/dev/null

for e in $(ls -d package/A/luci-*/po feeds/luci/applications/luci-*/po); do
    if [[ -d $e/zh-cn && ! -d $e/zh_Hans ]]; then
        ln -s zh-cn $e/zh_Hans 2>/dev/null
    elif [[ -d $e/zh_Hans && ! -d $e/zh-cn ]]; then
        ln -s zh_Hans $e/zh-cn 2>/dev/null
    fi
done

cat >organize.sh<<-EOF
	#!/bin/bash
	[ -d firmware ] || mkdir firmware
	FILE_NAME=\$SOURCE_REPO-\${REPO_BRANCH#*-}-\$KERNEL_VERSION-\$DEVICE_TARGET
	tar -zcf firmware/\$FILE_NAME-packages.tar.gz bin/packages
	[ \$FIRMWARE_TYPE ] && cp -f \$(find bin/targets/ -type f -name "*\$FIRMWARE_TYPE*") firmware
	cd firmware && md5sum * >\$FILE_NAME-md5-config.txt
	sed '/^$/d' \$OPENWRT_PATH/.config >>\$FILE_NAME-md5-config.txt
	# [[ \$SOURCE_REPO == immortalwrt ]] && \
	# rename 's/immortalwrt/\${{ env.SOURCE_REPO }}-\${{ env.LITE_BRANCH }}/' * || \
	# rename 's/openwrt/\${{ env.SOURCE_REPO }}-\${{ env.LITE_BRANCH }}/' *
	echo "FIRMWARE_PATH=\$PWD" >>\$GITHUB_ENV
EOF
status

[[ $CLASH_KERNEL = 'true' && $KERNEL_TARGET ]] && {
    step_name='下载openchash运行内核'; begin_time=$(date '+%H:%M:%S')
    [[ -d files/etc/openclash/core ]] || mkdir -p files/etc/openclash/core
    CLASH_META_URL="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-$KERNEL_TARGET.tar.gz"
    GEOIP_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geoip.dat"
    GEOSITE_URL="https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat"
    COUNTRY_URL="https://raw.githubusercontent.com/alecthw/mmdb_china_ip_list/release/Country.mmdb"
    wget -qO- $CLASH_META_URL | tar xOz >files/etc/openclash/core/clash_meta
    wget -qO- $GEOIP_URL >files/etc/openclash/GeoIP.dat
    wget -qO- $GEOSITE_URL >files/etc/openclash/GeoSite.dat
    wget -qO- $COUNTRY_URL >files/etc/openclash/Country.mmdb
    chmod +x files/etc/openclash/core/clash_meta
    status
}

[[ $ZSH_TOOL = 'true' ]] && {
    step_name='下载zsh终端工具'; begin_time=$(date '+%H:%M:%S')
    [[ -d files/root ]] || mkdir -p files/root
    git clone -q https://github.com/ohmyzsh/ohmyzsh files/root/.oh-my-zsh
    git clone -q https://github.com/zsh-users/zsh-autosuggestions files/root/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone -q https://github.com/zsh-users/zsh-syntax-highlighting files/root/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    git clone -q https://github.com/zsh-users/zsh-completions files/root/.oh-my-zsh/custom/plugins/zsh-completions
	cat >files/root/.zshrc<<-EOF
	# Path to your oh-my-zsh installation.
	ZSH=\$HOME/.oh-my-zsh
	# Set name of the theme to load.
	ZSH_THEME="ys"
	# Uncomment the following line to disable bi-weekly auto-update checks.
	DISABLE_AUTO_UPDATE="true"
	# Which plugins would you like to load?
	plugins=(git command-not-found extract z docker zsh-syntax-highlighting zsh-autosuggestions zsh-completions)
	source \$ZSH/oh-my-zsh.sh
	autoload -U compinit && compinit
	EOF
    status
}

[[ $CLASH_KERNEL = 'true' && $KERNEL_TARGET ]] && {
    step_name='下载adguardhome运行内核'; begin_time=$(date '+%H:%M:%S')
    [[ -d files/usr/bin/AdGuardHome ]] || mkdir -p files/usr/bin/AdGuardHome
    AGH_CORE="https://github.com/AdguardTeam/AdGuardHome/releases/latest/download/AdGuardHome_linux_$KERNEL_TARGET.tar.gz"
    wget -qO- $AGH_CORE | tar xOz >files/usr/bin/AdGuardHome/AdGuardHome
    chmod +x files/usr/bin/AdGuardHome/AdGuardHome
    status
}

step_name='更新配置文件'; begin_time=$(date '+%H:%M:%S')
make defconfig 1>/dev/null 2>&1
status

echo -e "$(color cy 当前编译机型) $(color cb $SOURCE_REPO-${REPO_BRANCH#*-}-$TARGET_DEVICE-$KERNEL_VERSION)"

sed -i "s/\$(VERSION_DIST_SANITIZED)/$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION/" include/image.mk
# sed -i "/IMG_PREFIX:/ {s/=/=$SOURCE_REPO-${REPO_BRANCH#*-}-$KERNEL_VERSION-\$(shell date +%y.%m.%d)-/}" include/image.mk

echo "UPLOAD_BIN_DIR=false" >>$GITHUB_ENV
echo "FIRMWARE_TYPE=$FIRMWARE_TYPE" >>$GITHUB_ENV

color cp "脚本运行完成！"
