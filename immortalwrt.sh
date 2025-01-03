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
    git clone -q $branch --depth=1 $repo_url $target_dir 2>/dev/null || {
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    }
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
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    }
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
    git clone -q $branch --depth=1 $repo_url $temp_dir 2>/dev/null || {
        print_info "$(color cr 拉取) $repo_url [ $(color cr ✕) ]"
        return 0
    }
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
			CONFIG_TARGET_KERNEL_PARTSIZE=16
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
			if [[ "${REPO_BRANCH#*-}" = "18.06" ]]; then
				cat >.config<<-EOF
				CONFIG_TARGET_brcm47xx=y
				CONFIG_TARGET_brcm47xx_mips74k=y
				CONFIG_TARGET_brcm47xx_mips74k_DEVICE_asus_rt-n16=y
				EOF
			else
				cat >.config<<-EOF
				CONFIG_TARGET_bcm47xx=y
				CONFIG_TARGET_bcm47xx_mips74k=y
				CONFIG_TARGET_bcm47xx_mips74k_DEVICE_asus_rt-n16=y
				EOF
			fi
			;;
		"armvirt-64")
			if [[ "$REPO_BRANCH" =~ 21.02|18.06 ]]; then
				cat >.config<<-EOF
				CONFIG_TARGET_armvirt=y
				CONFIG_TARGET_armvirt_64=y
				CONFIG_TARGET_armvirt_64_Default=y
				EOF
			else
				cat >.config<<-EOF
				CONFIG_TARGET_armsr=y
				CONFIG_TARGET_armsr_armv8=y
				CONFIG_TARGET_armsr_armv8_DEVICE_generic=y
				EOF
			fi
			KERNEL_TARGET=arm64
			;;
	esac
}

REPO_URL="https://github.com/immortalwrt/immortalwrt"
echo "REPO_URL=$REPO_URL" >>$GITHUB_ENV
step_name='拉取编译源码'; begin_time=$(date '+%H:%M:%S')
[[ $REPO_BRANCH != "master" ]] && BRANCH="-b $REPO_BRANCH --single-branch"
#cd /workdir
git clone -q $BRANCH $REPO_URL openwrt
status
#ln -sf /workdir/openwrt $GITHUB_WORKSPACE/openwrt
[[ -d openwrt ]] && cd openwrt || exit
echo "OPENWRT_PATH=$PWD" >>$GITHUB_ENV

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
CACHE_NAME="$SOURCE_REPO-${REPO_BRANCH#*-}-$DEVICE_TARGET-cache-$TOOLS_HASH"
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
clone_dir https://github.com/sbwml/openwrt_helloworld shadowsocks-rust

clone_dir https://github.com/coolsnowwolf/packages qtbase qttools qBittorrent qBittorrent-static bandwidthd
clone_dir https://github.com/kiddin9/kwrt-packages luci-app-bypass luci-app-pushbot
git_clone https://github.com/sbwml/packages_lang_golang golang
git_clone https://github.com/ilxp/luci-app-ikoolproxy
git_clone https://github.com/AlexZhuo/luci-app-bandwidthd
clone_all https://github.com/destan19/OpenAppFilter && rm -rf feeds/*/*/luci-app-appfilter
clone_all https://github.com/linkease/istore luci

[[ "$REPO_BRANCH" =~ 18.06 ]] && {
    clone_all v5-lua https://github.com/sbwml/luci-app-mosdns
    clone_all lua https://github.com/sbwml/luci-app-alist
    git_clone master https://github.com/UnblockNeteaseMusic/luci-app-unblockneteasemusic
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

[[ ! "$REPO_BRANCH" =~ 18.06 ]] && {
    clone_all https://github.com/brvphoenix/luci-app-wrtbwmon
    clone_all https://github.com/brvphoenix/wrtbwmon
    clone_all https://github.com/sbwml/luci-app-mosdns
    clone_all https://github.com/sbwml/luci-app-alist
    git_clone https://github.com/UnblockNeteaseMusic/luci-app-unblockneteasemusic
    git_clone https://github.com/kiddin9/luci-theme-edge
    git_clone https://github.com/jerrykuku/luci-theme-argon
    git_clone https://github.com/jerrykuku/luci-app-argon-config
    clone_dir openwrt-23.05 https://github.com/coolsnowwolf/luci luci-app-adguardhome
}

[[ "$REPO_BRANCH" =~ 21.02|18.06 ]] && {
    clone_dir https://github.com/immortalwrt/packages nghttp3 ngtcp2 bash
    clone_dir https://github.com/coolsnowwolf/packages docker dockerd containerd runc btrfs-progs
    clone_dir openwrt-23.05 https://github.com/immortalwrt/immortalwrt busybox ppp automount openssl \
        dnsmasq nftables libnftnl opkg fullconenat fullconenat-nft \
        #fstools odhcp6c iptables ipset dropbear usbmode
    clone_dir openwrt-23.05 https://github.com/immortalwrt/packages samba4 nginx-util htop pciutils libwebsockets gawk mwan3 \
        lua-openssl smartdns bluez curl #miniupnpc miniupnpd
    clone_dir openwrt-23.05 https://github.com/immortalwrt/luci luci-app-syncdial luci-app-mwan3
    clone_dir https://github.com/coolsnowwolf/lede ucode firewall4
}

[[ ! "$REPO_BRANCH" =~ 21.02|18.06 ]] && {
    git_clone https://github.com/immortalwrt/homeproxy luci-app-homeproxy
    clone_all https://github.com/morytyann/OpenWrt-mihomo
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
	CONFIG_PACKAGE_luci-app-appfilter=y
	CONFIG_PACKAGE_luci-app-arpbind=y
	CONFIG_PACKAGE_luci-app-bridge=y
	CONFIG_PACKAGE_luci-app-cowb-speedlimit=y
	CONFIG_PACKAGE_luci-app-cowbping=y
	CONFIG_PACKAGE_luci-app-cpulimit=y
	CONFIG_PACKAGE_luci-app-ddnsto=y
	CONFIG_PACKAGE_luci-app-diskman=y
	CONFIG_PACKAGE_luci-app-filebrowser=y
	CONFIG_PACKAGE_luci-app-filetransfer=y
	CONFIG_PACKAGE_luci-app-ikoolproxy=y
	CONFIG_PACKAGE_luci-app-luci-app-commands=y
	CONFIG_PACKAGE_luci-app-oaf=y
	CONFIG_PACKAGE_luci-app-opkg=y
	CONFIG_PACKAGE_luci-app-passwall=y
	CONFIG_PACKAGE_luci-app-ssr-plus=y
	CONFIG_PACKAGE_luci-app-timedtask=y
	CONFIG_PACKAGE_luci-app-tinynote=y
	CONFIG_PACKAGE_luci-app-ttyd=y
	CONFIG_PACKAGE_luci-app-upnp=y
	CONFIG_PACKAGE_luci-app-vlmcsd=y
	CONFIG_PACKAGE_luci-app-wifischedule=y
	CONFIG_PACKAGE_luci-app-wizard=y
	CONFIG_PACKAGE_default-settings-chn=y
	CONFIG_DEFAULT_SETTINGS_OPTIMIZE_FOR_CHINESE=y
	# CONFIG_LUCI_SRCDIET is not set #压缩 Lua 源代码
	# CONFIG_LUCI_JSMIN is not set #压缩 JavaScript 源代码
	# CONFIG_LUCI_CSSTIDY is not set #压缩 CSS 文件
EOF

# sed -i "/DISTRIB_DESCRIPTION/ {s/'$/-$SOURCE_REPO-$(date +%Y年%m月%d日)'/}" package/*/*/*/openwrt_release
sed -i "/VERSION_NUMBER/ s/if.*/if \$(VERSION_NUMBER),\$(VERSION_NUMBER),${REPO_BRANCH#*-}-SNAPSHOT)/" include/version.mk
sed -i "s/ImmortalWrt/OpenWrt/g" {$config_generate,include/version.mk}
sed -i "/listen_https/ {s/^/#/g}" package/*/*/*/files/uhttpd.config
sed -i "\$i uci -q set luci.main.mediaurlbase=\"/luci-static/bootstrap\" && uci -q commit luci\nuci -q set upnpd.config.enabled=\"1\" && uci -q commit upnpd\nsed -i 's/root::.*:::/root:\$1\$V4UetPzk\$CYXluq4wUazHjmCDBCqXF.::0:99999:7:::/g' /etc/shadow" $(find package/emortal/ -type f -regex '.*default-settings$')

[[ "$TARGET_DEVICE" =~ phicomm|newifi|asus ]] || {
    add_package "
    axel lscpu lsscsi patch diffutils htop lscpu
    brcmfmac-firmware-43430-sdio brcmfmac-firmware-43455-sdio kmod-brcmfmac
    kmod-brcmutil kmod-mt7601u kmod-mt76x0u kmod-mt76x2u kmod-r8125
    kmod-rt2500-usb kmod-rt2800-usb kmod-rtl8187 kmod-rtl8723bs
    kmod-rtl8723au kmod-rtl8723bu kmod-rtl8812au-ac kmod-rtl8812au-ct
    kmod-rtl8821ae kmod-rtl8821cu kmod-rtl8xxxu kmod-usb-net-asix-ax88179
    kmod-usb-net-rtl8150 kmod-usb-net-rtl8152 mt7601u-firmware #rtl8188eu-firmware #kmod-rtl8188eu
    rtl8723au-firmware rtl8723bu-firmware rtl8821ae-firmware
    luci-app-aria2
    luci-app-bypass
    #luci-app-cifs-mount
    luci-app-commands
    luci-app-hd-idle
    luci-app-cupsd
    luci-app-openclash
    luci-app-pushbot
    luci-app-softwarecenter
    #luci-app-syncdial
    #luci-app-transmission
    luci-app-usb-printer
    luci-app-vssr
    luci-app-wol
    #luci-app-bandwidthd
    luci-app-store
    luci-app-log
    #luci-app-alist
    luci-app-weburl
    luci-app-wrtbwmon
    luci-app-pwdHackDeny
    luci-app-uhttpd
    luci-app-zerotier
    luci-app-control-webrestriction
    luci-app-cowbbonding
    luci-theme-argon
    luci-app-argon-config
    "
    trv=$(awk -F= '/PKG_VERSION:/{print $2}' feeds/packages/net/transmission/Makefile)
    [[ $trv ]] && wget -qO feeds/packages/net/transmission/patches/tr$trv.patch \
    raw.githubusercontent.com/hong0980/diy/master/files/transmission/tr$trv.patch

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

    mwan3=feeds/packages/net/mwan3/files/etc/config/mwan3
    grep -q "8.8" $mwan3 && sed -i '/8.8/d' $mwan3

    grep -q "rblibtorrent" package/A/qBittorrent/Makefile && \
    sed -i 's/+rblibtorrent/+libtorrent-rasterbar/' package/A/qBittorrent/Makefile

    [[ "$REPO_BRANCH" =~ 2.*0 ]] && {
        sed -i 's/^ping/-- ping/g' package/*/*/*/*/*/bridge.lua
    } || {
        for d in $(find feeds/ package/ -type f -name "index.htm" 2>/dev/null); do
            if grep -q "Kernel Version" $d; then
                sed -i 's|os.date(.*|os.date("%F %X") .. " " .. translate(os.date("%A")),|' $d
                sed -i '/<%+footer%>/i<%-\n\tlocal incdir = util.libpath() .. "/view/admin_status/index/"\n\tif fs.access(incdir) then\n\t\tlocal inc\n\t\tfor inc in fs.dir(incdir) do\n\t\t\tif inc:match("%.htm$") then\n\t\t\t\tinclude("admin_status/index/" .. inc:gsub("%.htm$", ""))\n\t\t\tend\n\t\tend\n\t\end\n-%>\n' $d
                # sed -i '/<%+footer%>/i<fieldset class="cbi-section">\n\t<legend><%:天气%></legend>\n\t<table width="100%" cellspacing="10">\n\t\t<tr><td width="10%"><%:本地天气%></td><td > <iframe width="900" height="120" frameborder="0" scrolling="no" hspace="0" src="//i.tianqi.com/?c=code&a=getcode&id=22&py=xiaoshan&icon=1"></iframe>\n\t\t<tr><td width="10%"><%:柯桥天气%></td><td > <iframe width="900" height="120" frameborder="0" scrolling="no" hspace="0" src="//i.tianqi.com/?c=code&a=getcode&id=22&py=keqiaoqv&icon=1"></iframe>\n\t\t<tr><td width="10%"><%:指数%></td><td > <iframe width="400" height="270" frameborder="0" scrolling="no" hspace="0" src="https://i.tianqi.com/?c=code&a=getcode&id=27&py=xiaoshan&icon=1"></iframe><iframe width="400" height="270" frameborder="0" scrolling="no" hspace="0" src="https://i.tianqi.com/?c=code&a=getcode&id=27&py=keqiaoqv&icon=1"></iframe>\n\t</table>\n</fieldset>\n' $d
            fi
        done
    }

    xb=$(find_dir "package/ feeds/" "luci-app-bypass")
    [[ -d $xb ]] && sed -i 's/default y/default n/g' $xb/Makefile
    qBittorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*-\K\d+\.\d+\.\d+')
    libtorrent_version=$(curl -sL api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep -oP 'tag_name.*v\K\d+\.\d+\.\d+')
    xc=$(find_dir "package/ feeds/" "qBittorrent-static")
    [[ -d $xc ]] && sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=${qBittorrent_version:-4.6.5}_v${libtorrent_version:-2.0.10}/" $xc/Makefile
    xd=$(find_dir "package/ feeds/" "luci-app-turboacc")
    [[ -d $xd ]] && sed -i '/hw_flow/s/1/0/;/sfe_flow/s/1/0/;/sfe_bridge/s/1/0/' $xd/root/etc/config/turboacc
    xe=$(find_dir "package/ feeds/" "luci-app-ikoolproxy")
    [[ -f $xe/luasrc/model/cbi/koolproxy/basic.lua ]] && sed -i '/^local.*sys.exec/ s/$/ or 0/g; /^local.*sys.exec/ s/.txt/.txt 2>\/dev\/null/g' $xe/luasrc/model/cbi/koolproxy/basic.lua
    xg=$(find_dir "package/ feeds/" "luci-app-pushbot")
    [[ -d $xg ]] && {
        sed -i "s|-c pushbot|/usr/bin/pushbot/pushbot|" $xg/luasrc/controller/pushbot.lua
        sed -i '/start()/a[ "$(uci get pushbot.@pushbot[0].pushbot_enable)" -eq "0" ] && return 0' $xg/root/etc/init.d/pushbot
    }
}

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
        #luci-app-adguardhome
        luci-app-passwall2
        #luci-app-amule
        luci-app-dockerman
        luci-app-netdata
        luci-app-poweroff
        luci-app-qbittorrent
        #luci-app-smartdns
        luci-app-ikoolproxy
        luci-app-deluge
        #luci-app-godproxy
        #luci-app-frpc
        luci-app-unblockneteasemusic
        #AmuleWebUI-Reloaded htop lscpu lsscsi lsusb nano pciutils screen webui-aria2 zstd pv
        #subversion-client #unixodbc #git-http
        "
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        [[ $REPO_BRANCH == master ]] && rm -rf package/kernel/rt*
        ;;
    "r1-plus-lts"|"r1-plus"|"r4s"|"r2c"|"r2s")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "
        luci-app-dockerman
        luci-app-turboacc
        luci-app-qbittorrent
        luci-app-passwall2
        luci-app-netdata
        luci-app-cpufreq
        #luci-app-adguardhome
        #luci-app-amule
        luci-app-deluge
        #luci-app-smartdns
        #luci-app-adbyby-plus
        luci-app-unblockneteasemusic
        #htop lscpu lsscsi #nano screen #zstd pv ethtool
        "
        [[ "${REPO_BRANCH#*-}" =~ ^2 ]] && sed -i '/bridge/d' .config
        wget -qO package/base-files/files/bin/bpm git.io/bpm && chmod +x package/base-files/files/bin/bpm
        wget -qO package/base-files/files/bin/ansi git.io/ansi && chmod +x package/base-files/files/bin/ansi
        add_package "kmod-rt2800-usb kmod-rtl8187 kmod-rtl8812au-ac kmod-rtl8812au-ct kmod-rtl8821ae
        kmod-rtl8821cu ethtool kmod-usb-wdm kmod-usb2 kmod-usb-ohci kmod-usb-uhci kmod-mt76x2u kmod-mt76x0u
        kmod-gpu-lima luci-app-cpufreq luci-app-pushbot luci-app-wrtbwmon luci-app-vssr"
        echo -e "CONFIG_DRIVER_11AC_SUPPORT=y\nCONFIG_DRIVER_11N_SUPPORT=y\nCONFIG_DRIVER_11W_SUPPORT=y" >>.config
        [[ $TARGET_DEVICE =~ r1-plus-lts ]] && sed -i "/lan_wan/s/'.*' '.*'/'eth0' 'eth1'/" target/*/rockchip/*/*/*/*/02_network
        ;;
    "armvirt-64")
        if [[ "$REPO_BRANCH" =~ 21.02|18.06 ]]; then
            FIRMWARE_TYPE="default-rootfs"
        else
            FIRMWARE_TYPE="generic-rootfs"
        fi
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "
        perl perl-http-date perlbase-file perlbase-getopt perlbase-time perlbase-unicode
        perlbase-utf8 blkid fdisk lsblk parted attr btrfs-progs chattr dosfstools e2fsprogs
        f2fs-tools f2fsck lsattr mkf2fs xfs-fsck xfs-mkfs bsdtar pigz bash gawk getopt
        losetup tar uuidgen acpid kmod-brcmfmac kmod-brcmutil kmod-cfg80211 kmod-mac80211
        hostapd-common wpa-cli wpad-basic iw ntfs3-mount coreutils coreutils-base64 jq pv
        coreutils-nohup
        "
        echo -e "CONFIG_BTRFS_PROGS_ZSTD=y\nCONFIG_BRCMFMAC_SDIO=y" >>.config
        echo "CONFIG_PERL_NOCOMMENT=y" >>.config
        sed -i -E '/easymesh/d' .config
        sed -i "s/default 160/default $PART_SIZE/" config/Config-images.in
        sed -i 's/arm/arm||TARGET_armvirt_64/g' $(find_dir "package/ feeds/" "luci-app-cpufreq")/Makefile
        ;;
    "newifi-d2")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
    "phicomm_k2p")
        FIRMWARE_TYPE="sysupgrade"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        add_package "luci-app-wifischedule"
        sed -i '/diskman/d;/autom/d;/ikoolproxy/d;/autos/d' .config
        ;;
    "asus_rt-n16")
        FIRMWARE_TYPE="n16"
        [[ -n $DEFAULT_IP ]] && \
        sed -i '/n) ipad/s/".*"/"'"$DEFAULT_IP"'"/' $config_generate || \
        sed -i '/n) ipad/s/".*"/"192.168.2.1"/' $config_generate
        ;;
esac

[[ "$REPO_BRANCH" =~ 21.02|18.06 ]] && {
	cat <<-\EOF >>package/kernel/linux/modules/netfilter.mk
	define KernelPackage/nft-tproxy
	  SUBMENU:=$(NF_MENU)
	  TITLE:=Netfilter nf_tables tproxy support
	  DEPENDS:=+kmod-nft-core +kmod-nf-tproxy +kmod-nf-conntrack
	  FILES:=$(foreach mod,$(NFT_TPROXY-m),$(LINUX_DIR)/net/$(mod).ko)
	  AUTOLOAD:=$(call AutoProbe,$(notdir $(NFT_TPROXY-m)))
	  KCONFIG:=$(KCONFIG_NFT_TPROXY)
	endef
	$(eval $(call KernelPackage,nft-tproxy))
	define KernelPackage/nf-tproxy
	  SUBMENU:=$(NF_MENU)
	  TITLE:=Netfilter tproxy support
	  KCONFIG:= $(KCONFIG_NF_TPROXY)
	  FILES:=$(foreach mod,$(NF_TPROXY-m),$(LINUX_DIR)/net/$(mod).ko)
	  AUTOLOAD:=$(call AutoProbe,$(notdir $(NF_TPROXY-m)))
	endef
	$(eval $(call KernelPackage,nf-tproxy))
	define KernelPackage/nft-compat
	  SUBMENU:=$(NF_MENU)
	  TITLE:=Netfilter nf_tables compat support
	  DEPENDS:=+kmod-nft-core +kmod-nf-ipt
	  FILES:=$(foreach mod,$(NFT_COMPAT-m),$(LINUX_DIR)/net/$(mod).ko)
	  AUTOLOAD:=$(call AutoProbe,$(notdir $(NFT_COMPAT-m)))
	  KCONFIG:=$(KCONFIG_NFT_COMPAT)
	endef
	$(eval $(call KernelPackage,nft-compat))
	define KernelPackage/ipt-socket
	  TITLE:=Iptables socket matching support
	  DEPENDS+=+kmod-nf-socket +kmod-nf-conntrack
	  KCONFIG:=$(KCONFIG_IPT_SOCKET)
	  FILES:=$(foreach mod,$(IPT_SOCKET-m),$(LINUX_DIR)/net/$(mod).ko)
	  AUTOLOAD:=$(call AutoProbe,$(notdir $(IPT_SOCKET-m)))
	  $(call AddDepends/ipt)
	endef
	define KernelPackage/ipt-socket/description
	  Kernel modules for socket matching
	endef
	$(eval $(call KernelPackage,ipt-socket))
	define KernelPackage/nf-socket
	  SUBMENU:=$(NF_MENU)
	  TITLE:=Netfilter socket lookup support
	  KCONFIG:= $(KCONFIG_NF_SOCKET)
	  FILES:=$(foreach mod,$(NF_SOCKET-m),$(LINUX_DIR)/net/$(mod).ko)
	  AUTOLOAD:=$(call AutoProbe,$(notdir $(NF_SOCKET-m)))
	endef
	$(eval $(call KernelPackage,nf-socket))
	EOF
    curl -sSo include/openssl-module.mk https://raw.githubusercontent.com/immortalwrt/immortalwrt/master/include/openssl-module.mk
}

[[ "$REPO_BRANCH" =~ master ]] && sed -i '/deluge/d' .config
sed -i '/bridge\|vssr\|deluge/d' .config

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
