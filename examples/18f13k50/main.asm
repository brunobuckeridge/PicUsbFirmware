; USB Firmware for PICs
; main routine and configuration
; Copyright (C) 2012 Holger Oehm
;
; Licensed under the Apache License, Version 2.0 (the "License");
; you may not use this file except in compliance with the License.
; You may obtain a copy of the License at
;
;     http://www.apache.org/licenses/LICENSE-2.0
;
; Unless required by applicable law or agreed to in writing, software
; distributed under the License is distributed on an "AS IS" BASIS,
; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
; See the License for the specific language governing permissions and
; limitations under the License.

#include <p18f13k50.inc>

;**************************************************************
; configuration
	config USBDIV	= ON
	config FOSC	= HS
	config PLLEN	= ON
        config FCMEN	= OFF
        config IESO     = OFF
	config WDTEN	= OFF
        config WDTPS    = 32768
        config MCLRE    = ON
        config STVREN   = ON
        config LVP      = OFF
        config XINST    = OFF
        config CP0      = OFF
        config CP1      = OFF
        config CPB      = OFF
        config CPD      = OFF
        config WRT0     = OFF
        config WRT1     = OFF
        config WRTB     = OFF
        config WRTC     = OFF
        config WRTD     = OFF
        config EBTR0    = OFF
        config EBTR1    = OFF
;**************************************************************
; exported subroutines
	global	main
	global	highPriorityInterrupt
	global	lowPriorityInterrupt

;**************************************************************
; imported subroutines
; usb.asm
	extern	InitUSB
	extern	WaitConfiguredUSB
	extern	ServiceUSB
	extern	enableUSBInterrupts
	extern	sleepUsbSuspended
	extern	USB_received

;**************************************************************
; imported variables
; usb.asm
	extern	LED_states

;**************************************************************
; local definitions
#define TIMER0H_VAL         0xFE
#define TIMER0L_VAL         0x20

;**************************************************************
; local data
main_udata		UDATA
noSignFromHostL		RES	1
noSignFromHostH		RES	1
blinkenLights		RES	1
; low prio interrupt has to save registers for itself
STATUS_temp_LP		RES	1
BSR_temp_LP		RES	1
FSR0H_temp_LP		RES	1
FSR0L_temp_LP		RES	1
FSR1H_temp_LP		RES	1
FSR1L_temp_LP		RES	1
FSR2H_temp_LP		RES	1
FSR2L_temp_LP		RES	1
; high prio interrupt needs to save only FSRn
FSR0H_temp_HP		RES	1
FSR0L_temp_HP		RES	1
FSR1H_temp_HP		RES	1
FSR1L_temp_HP		RES	1
FSR2H_temp_HP		RES	1
FSR2L_temp_HP		RES	1
;**************************************************************
; local data in accessbank
main_accessbank		UDATA_ACS
W_temp_LP		RES	1

;**************************************************************
; main code
main_code		CODE

highPriorityInterrupt
	movff	FSR0H, FSR0H_temp_HP
	movff	FSR0L, FSR0L_temp_HP
	movff	FSR1H, FSR1H_temp_HP
	movff	FSR1L, FSR1L_temp_HP
	movff	FSR2H, FSR2H_temp_HP
	movff	FSR2L, FSR2L_temp_HP

;	call	HPinterruptHandler

	movff	FSR2L_temp_HP, FSR2L
	movff	FSR2H_temp_HP, FSR2H
	movff	FSR1L_temp_HP, FSR1L
	movff	FSR1H_temp_HP, FSR1H
	movff	FSR0L_temp_HP, FSR0L
	movff	FSR0H_temp_HP, FSR0H
	retfie	FAST

lowPriorityInterrupt
	movff	STATUS, STATUS_temp_LP
	movwf	W_temp_LP, ACCESS
	movff	BSR, BSR_temp_LP
	movff	FSR0H, FSR0H_temp_LP
	movff	FSR0L, FSR0L_temp_LP
	movff	FSR1H, FSR1H_temp_LP
	movff	FSR1L, FSR1L_temp_LP
	movff	FSR2H, FSR2H_temp_LP
	movff	FSR2L, FSR2L_temp_LP

;	dispatch interrupt
	btfss	PIR2, USBIF, ACCESS
	goto	dispatchLowPrioInterrupt_usbDone
	call	ServiceUSB
	bcf	PIR2, USBIF, ACCESS

dispatchLowPrioInterrupt_usbDone

	movff	FSR2L_temp_LP, FSR2L
	movff	FSR2H_temp_LP, FSR2H
	movff	FSR1L_temp_LP, FSR1L
	movff	FSR1H_temp_LP, FSR1H
	movff	FSR0L_temp_LP, FSR0L
	movff	FSR0H_temp_LP, FSR0H
	movff	BSR_temp_LP, BSR
	movf	W_temp_LP, W, ACCESS
	movff	STATUS_temp_LP, STATUS
	retfie

main
	clrf	LATB, ACCESS
	movlw	b'10001111'		; LEDs on Port B, RB<4:6>
	movwf	TRISB, ACCESS

	call	setupTimer0

	call	InitUSB			; initialize the USB module

	call	WaitConfiguredUSB

	; set up interrupt configuration
	clrf	INTCON, ACCESS		; all interrupts off
	clrf	INTCON3, ACCESS		; external interrupts off
	clrf	PIR1, ACCESS		; clear interrupt sources
	clrf	PIR2, ACCESS		; clear interrupt sources
	clrf	PIE1, ACCESS		; disable external interrupts
	clrf	PIE2, ACCESS		; disable external interrupts
	clrf	IPR1, ACCESS		; set priority to low
	clrf	IPR2, ACCESS		; set priority to low
	
	bsf	RCON, IPEN, ACCESS	; enable interrupt priority
	
	call	enableUSBInterrupts	; enable interrupts from the usb module
	bsf	PIE2, USBIF		; enable USB interrupts
	bsf	INTCON, GIEH		; enable high prio interrupt vector
	bsf	INTCON, GIEL		; enable low prio interrupt vector
	
	banksel	noSignFromHostL
	clrf	noSignFromHostL, BANKED
	clrf	noSignFromHostH, BANKED
	clrf	blinkenLights, BANKED
	movlw	b'01110000'		; switch all leds off (inverted)
	movwf	LATB,ACCESS

mainLoop
	banksel	USB_received
	bcf	USB_received,0,BANKED
waitTimerLoop
	btfss	INTCON, T0IF, ACCESS
	goto	waitTimerLoop

	call	setupTimer0

	; start by switching off all LEDs
	movlw	b'01110000'
	movwf	LATB,ACCESS
	; sleep as long as we are in suspend mode
	call	sleepUsbSuspended

	banksel	USB_received
	btfsc	USB_received,0,BANKED
	goto	ledsChangedByHost

	; nothing new from the host
	; first divider: 10ms * 256 = 2.5s
	banksel	noSignFromHostL
	incfsz	noSignFromHostL, BANKED
	goto	setLeds

	btfss	blinkenLights,7,BANKED	; already blinking?
	goto	notYetBlinking		; no not yet
	incf	blinkenLights,F,BANKED
	btfsc	blinkenLights,1,BANKED	; changes every time: blinking period is 5.2s
	goto	yellowOn
	; set led state to all off
	banksel	LED_states
	clrf	LED_states, BANKED
	clrf	LED_states+1, BANKED
	clrf	LED_states+2, BANKED
	movwf	LATB,ACCESS
	goto	setLeds

notYetBlinking
	incf	noSignFromHostH,F,BANKED
	btfss	noSignFromHostH,5,BANKED; 32*256*10ms ~= 82 seconds nothing from the host
	goto	setLeds			; not yet long enough
yellowOn
	clrf	blinkenLights,BANKED	; reset blink counter
	bsf	blinkenLights,7,BANKED
	bsf	LED_states+1, 0, BANKED
	goto	setLeds

	; set leds according to led state, inverted logic. Use bits 4:6
setled	macro	index
	btfss	LED_states + index, 0, BANKED
	bsf	LATB, index + 4, ACCESS	; bit 0 cleared, set port bit
	btfsc	LED_states + index, 0, BANKED
	bcf	LATB, index + 4, ACCESS	; bit 0 set, clear port bit
	endm

ledsChangedByHost
	banksel	noSignFromHostL
	clrf	noSignFromHostL, BANKED
	clrf	noSignFromHostH, BANKED
	clrf	blinkenLights, BANKED

setLeds
	banksel	LED_states
	setled	0	; red
	setled	1	; yellow
	setled	2	; green

	goto mainLoop

setupTimer0
	bcf	INTCON, T0IF, ACCESS	; clear Timer0 interrupt flag
	; reload start value
	movlw	TIMER0H_VAL
	movwf	TMR0H, ACCESS
	movlw	TIMER0L_VAL
	movwf	TMR0L, ACCESS
	; configure timer0: enable, 16 bit, internal clock, 256 prescaler
	movlw	( 1 << TMR0ON ) | ( b'0111' )
	movwf	T0CON, ACCESS

	return

			END
