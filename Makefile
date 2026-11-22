# FUNForth Makefile - builds kernel.img and runs the QEMU test harness.
#
# Toolchain: arm-none-eabi-gcc used as assembler+linker only.
# QEMU: qemu-system-arm (override with QEMU_SYSTEM_ARM=...).

ifeq ($(shell command -v arm-none-eabi-gcc 2>/dev/null),)
CROSS := $(HOME)/toolchains/arm-gcc/bin/arm-none-eabi-
else
CROSS := arm-none-eabi-
endif

CFLAGS  := -nostdlib -nostartfiles -ffreestanding -mfloat-abi=soft \
           -march=armv6k -O2 -Wall
ASFLAGS := $(CFLAGS)
LDFLAGS := -nostdlib -T link.ld

SRC := src/seed.S src/hal-2835.S src/hal-2837.S
OBJ := $(SRC:.S=.o)

QEMU_PY := python3 tools/qemu-ctl.py

all: kernel.img kernel.elf

kernel.elf: $(OBJ) link.ld
	$(CROSS)gcc $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ)

kernel.img: kernel.elf
	$(CROSS)objcopy -O binary $< $@

%.o: %.S
	$(CROSS)gcc $(ASFLAGS) -c -o $@ $<

# QEMU loads a raw -kernel image at 0x10000 on raspi models, so the harness
# boots kernel.elf (linked at the architectural 0x8000). Hardware boots the
# raw kernel.img at 0x8000 via the GPU firmware.
run: kernel.elf
	$(QEMU_PY) --run --kernel kernel.elf

test: kernel.elf
	$(QEMU_PY) --kernel kernel.elf --script test/all.fth --expected test/expected.txt

test-fb test-sd: kernel.img
	@echo "$@ requires a later milestone (see SPEC.md)" && exit 1

clean:
	rm -f $(OBJ) kernel.elf kernel.img

.PHONY: all run test test-fb test-sd clean
