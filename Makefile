TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DarkJIT

# --- App core ---
DarkJIT_FILES = main.m AppDelegate.m DarkJITViewController.m DJAppCell.m
DarkJIT_FILES += AppListManager.m jit_enabler.m LogTextView.m

# --- kexploit ---
DarkJIT_FILES += kexploit/kexploit_opa334.m kexploit/krw.m kexploit/kutils.m
DarkJIT_FILES += kexploit/offsets.m kexploit/vnode.m

# --- kpf ---
DarkJIT_FILES += kpf/patchfinder.m

# --- utils ---
DarkJIT_FILES += utils/file.m utils/hexdump.m utils/process.m utils/sandbox.m

# --- TaskRop ---
DarkJIT_FILES += TaskRop/RemoteCall.m TaskRop/PAC.m TaskRop/VM.m
DarkJIT_FILES += TaskRop/Thread.m TaskRop/Exception.m TaskRop/MigFilterBypassThread.m

# --- research ---
DarkJIT_FILES += research/amfi_research.m research/sandbox_research.m research/vnode_research.m

# --- XPF ---
DarkJIT_FILES += XPF/src/xpf.c XPF/src/common.c XPF/src/decompress.c
DarkJIT_FILES += XPF/src/bad_recovery.c XPF/src/non_ppl.c XPF/src/ppl.c

# --- ChOma ---
DarkJIT_FILES += XPF/external/ChOma/src/arm64.c XPF/external/ChOma/src/Base64.c
DarkJIT_FILES += XPF/external/ChOma/src/BufferedStream.c XPF/external/ChOma/src/CodeDirectory.c
DarkJIT_FILES += XPF/external/ChOma/src/CSBlob.c XPF/external/ChOma/src/DER.c
DarkJIT_FILES += XPF/external/ChOma/src/DyldSharedCache.c XPF/external/ChOma/src/Entitlements.c
DarkJIT_FILES += XPF/external/ChOma/src/Fat.c XPF/external/ChOma/src/FileStream.c
DarkJIT_FILES += XPF/external/ChOma/src/Host.c XPF/external/ChOma/src/MachO.c
DarkJIT_FILES += XPF/external/ChOma/src/MachOLoadCommand.c XPF/external/ChOma/src/MemoryStream.c
DarkJIT_FILES += XPF/external/ChOma/src/PatchFinder.c XPF/external/ChOma/src/PatchFinder_arm64.c
DarkJIT_FILES += XPF/external/ChOma/src/Util.c

# --- Flags ---
DarkJIT_CFLAGS = -I$(PWD)/include -I$(PWD) -I$(PWD)/XPF/src -I$(PWD)/XPF/external/ChOma/include \
    -I$(PWD)/XPF/external/ChOma/src \
    -I$(PWD)/kexploit -I$(PWD)/kpf -I$(PWD)/utils -I$(PWD)/TaskRop -I$(PWD)/research \
    -Wno-unused-function -Wno-unused-variable -Wno-unused-but-set-variable \
    -Wno-incompatible-pointer-types -Wno-incompatible-pointer-types-discards-qualifiers \
    -Wno-deprecated-declarations -Wno-nonportable-include-path -Wno-format \
    -fobjc-arc

DarkJIT_CCFLAGS = $(DarkJIT_CFLAGS)
DarkJIT_OBJCFLAGS = $(DarkJIT_CFLAGS)
DarkJIT_OBJCCFLAGS = $(DarkJIT_CFLAGS)

DarkJIT_FRAMEWORKS = UIKit Foundation IOKit CoreFoundation
DarkJIT_PRIVATE_FRAMEWORKS = IOSurface MobileCoreServices
DarkJIT_LIBRARIES = z sandbox
DarkJIT_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
