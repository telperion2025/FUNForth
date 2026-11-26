# FUNForth Makefile - builds kernel.img, the SD image, and runs the QEMU tests.
#
# Toolchain: arm-none-eabi-gcc used as assembler+linker only.
# QEMU: qemu-system-arm (override with QEMU_SYSTEM_ARM=...).
#
# From M12 the kernel embeds only forth/core.fth + drivers/sd.fth (comment-
# stripped into build/); the timer/GPIO/mailbox drivers live on the SD card
# (build/sd.img) and are loaded at cold boot via BOOT.LST -> sd-boot.

ifeq ($(shell command -v arm-none-eabi-gcc 2>/dev/null),)
CROSS := $(HOME)/toolchains/arm-gcc/bin/arm-none-eabi-
else
CROSS := arm-none-eabi-
endif

CFLAGS  := -nostdlib -nostartfiles -ffreestanding -mfloat-abi=soft \
           -march=armv6k -O2 -Wall
# -Wa,-I so .incbin "build/core.fth" resolves (cpp temp files break relative paths)
ASFLAGS := $(CFLAGS) -Wa,-I$(CURDIR)
LDFLAGS := -nostdlib -T link.ld

SRC := src/seed.S src/hal-2835.S src/hal-2837.S
OBJ := $(SRC:.S=.o)

# comment/whitespace-stripped sources embedded into the kernel via .incbin
EMBED := build/core.fth build/sd.fth

QEMU_PY := python3 tools/qemu-ctl.py

SD_FILES := BOOT.LST=sd/boot.lst TIMER.FTH=drivers/timer.fth \
            GPIO.FTH=drivers/gpio.fth MBOX.FTH=drivers/mailbox.fth \
            HELLO.TXT=sd/hello.txt FB.FTH=drivers/fb.fth VDI.FTH=drivers/vdi.fth \
            FONT8X16.FTH=drivers/font8x16.fth CON-FB.FTH=drivers/console-fb.fth \
            TASKS.FTH=forth/tasks.fth ASM.FTH=forth/asm.fth WM.FTH=wm.fth \
            TERM.FTH=term.fth GUI.FTH=gui.fth HELLO.FTH=hello.fth

all: kernel.img kernel.elf

build:
	mkdir -p build

build/core.fth: forth/core.fth | build
	sed 's/\\.*//; s/^[[:space:]]*//; s/[[:space:]]*$$//' $< | sed '/^$$/d' > $@

build/sd.fth: drivers/sd.fth | build
	sed 's/\\.*//; s/^[[:space:]]*//; s/[[:space:]]*$$//' $< | sed '/^$$/d' > $@

kernel.elf: $(OBJ) link.ld $(EMBED)
	$(CROSS)gcc $(CFLAGS) $(LDFLAGS) -o $@ $(OBJ)

kernel.img: kernel.elf
	$(CROSS)objcopy -O binary $< $@

%.o: %.S
	$(CROSS)gcc $(ASFLAGS) -c -o $@ $<

# seed.S .incbin's the stripped build/*.fth: rebuild when they change
src/seed.o: $(EMBED)

build/sd.img: tools/mksd.py sd/boot.lst sd/hello.txt drivers/timer.fth drivers/gpio.fth drivers/mailbox.fth drivers/fb.fth drivers/vdi.fth drivers/font8x16.fth drivers/console-fb.fth forth/tasks.fth forth/asm.fth wm.fth term.fth gui.fth hello.fth | build
	python3 tools/mksd.py $@ 32 $(SD_FILES)

# QEMU loads a raw -kernel image at 0x10000 on raspi models, so the harness
# boots kernel.elf (linked at the architectural 0x8000). Hardware boots the
# raw kernel.img at 0x8000 via the GPU firmware.
run: kernel.elf build/sd.img
	$(QEMU_PY) --run --kernel kernel.elf --sd build/sd.img

test: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/all.fth --wait-for "ok> " --expected test/expected.txt

test-sd: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/sd.fth --wait-for "ok> " --expected test/expected-sd.txt

test-fb: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/fb.fth --wait-for "ok> " --screendump build/fb.ppm --idle 3 --timeout 90
	python3 tools/fbcheck.py build/fb.ppm test/expected-fb.txt
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/fbcon.fth --wait-for "ok> " --screendump build/fbcon.ppm --idle 3 --timeout 90
	python3 tools/fbcheck.py build/fbcon.ppm test/expected-fbcon.txt

test-tasks: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/tasks.fth --wait-for "ok> " --expected test/expected-tasks.txt

test-preempt: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/preempt.fth --wait-for "ok> " --expected test/expected-preempt.txt

test-asm: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/asm.fth --wait-for "ok> " --expected test/expected-asm.txt

test-gui: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/gui.fth --wait-for "ok> " --expected test/expected-gui.txt --screendump build/gui.ppm --idle 3 --timeout 90
	python3 tools/fbcheck.py build/gui.ppm test/expected-gui-fb.txt

test-term: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/term.fth --wait-for "ok> " --expected test/expected-term.txt --screendump build/term.ppm --idle 3 --timeout 90
	python3 tools/fbcheck.py build/term.ppm test/expected-term-fb.txt

test-hello: kernel.elf build/sd.img
	$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/hello.fth --wait-for "ok> " --expected test/expected-hello.txt --screendump build/hello.ppm --idle 3 --timeout 90
	python3 tools/fbcheck.py build/hello.ppm test/expected-hello-fb.txt

test-probe: kernel.elf build/sd.img
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p33.fth --wait-for "ok> " --timeout 25
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p34.fth --wait-for "ok> " --timeout 25
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p35.fth --wait-for "ok> " --timeout 25
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p36.fth --wait-for "ok> " --timeout 25
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p37.fth --wait-for "ok> " --timeout 25
	-$(QEMU_PY) --kernel kernel.elf --sd build/sd.img --script test/p38.fth --wait-for "ok> " --timeout 25

# host-side checks, no ARM toolchain/QEMU needed
test-host:
	python3 tools/hosttest.py

clean:
	rm -rf build $(OBJ) kernel.elf kernel.img

.PHONY: all run test test-fb test-sd test-tasks test-preempt test-asm test-gui test-term test-hello test-probe test-host clean
