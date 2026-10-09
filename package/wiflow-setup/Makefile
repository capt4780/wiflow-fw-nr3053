include $(TOPDIR)/rules.mk

PKG_NAME:=wiflow-setup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_PARALLEL:=0

include $(INCLUDE_DIR)/package.mk

define Package/wiflow-setup
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Wiflow Setup for Viettel NR3053 (public source candidate)
  DEPENDS:=+uhttpd +uclient-fetch +iwinfo +iw +jsonfilter +firewall4 +ca-bundle +dnsmasq-full +nftables-json +mtwifi-cfg-ucode
endef

define Package/wiflow-setup/description
  Source-only Wiflow NR3053 experimental package for ImmortalWrt 25.12 APK.
  Assets excluded; first-boot and recovery gates remain incomplete.
  DO NOT FLASH: security and on-device network gates are not validated.
endef

define Package/wiflow-setup/conffiles
/etc/config/wiflow
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/rootfs
	$(CP) ./files/. $(PKG_BUILD_DIR)/rootfs/
endef

define Build/Compile
endef

define Package/wiflow-setup/install
	$(INSTALL_DIR) $(1)
	$(CP) $(PKG_BUILD_DIR)/rootfs/. $(1)/
endef

$(eval $(call BuildPackage,wiflow-setup))
