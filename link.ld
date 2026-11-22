/* FUNForth linker script: raw kernel loaded at 0x8000 by the Pi firmware. */
ENTRY(reset)

SECTIONS
{
  . = 0x8000;

  .text : {
    KEEP(*(.text.boot))
    *(.text*)
  }

  .rodata : { *(.rodata*) }
  .data   : { *(.data*) }

  .bss (NOLOAD) : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  }

  /DISCARD/ : {
    *(.comment*)
    *(.note*)
    *(.ARM.attributes)
    *(.ARM.exidx*)
    *(.eh_frame*)
  }
}
