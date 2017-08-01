Software
########

MQTT Topics
===========

See ``init3.lua`` and calls to ``logdata``, but in summary:

* Topics set by the device:

  * ``.../boot`` -- heartbeat, boot announcement, and LWT.
  * ``.../th``   -- temperature probe result
  * ``.../zz``   -- temporary debug topic

* Topics set by the user/controller:

  * ``.../fan``    -- ``on`` or ``1`` to force fan on, otherwise automatic.
  * ``.../mode``   -- ``off``, ``cool``, ``heat``, or ``emht``
  * ``.../target`` -- the target temperature, in half-degrees Celsius 

.. note::

   Temperatures are reported and consumed (in ``.../target``) in half
   degrees Celsius.  (Funky, ain't it?)

Control-side
============

I suggest a wrapper shell script, possibly named ``thermostat.sh`` or
something, along these lines, filling in the ``...`` appropriately::

   #!/bin/bash
   mosquitto_pub -h ... -u ... -P ... -t ".../$1" -m "$2" "${@:3}"

Then it's a matter of ``./thermostat.sh fan on``, ``./thermostat.sh mode
cool``, or ``./thermostat.sh target 50``.

Help!  My broker's down!  My network's down!
============================================

Don't panic!  If your network is still online, you can telnet in to the
device.  Failing that, the serial console is still viable (best grab the
pins with your own TTL adapter, as the nodemcu board has its own voltage
regulator and will attempt to power the thermostat's 3.3V rail from USB,
potentially fighting the other voltage regulator!).  Failing that, just put
the original thermostat back, yeah?

In any case, you can simulate the receipt of a MQTT message from the Lua
interpreter prompt (or ``diag exec`` via ``telnetd``).  Try one of these::

  nwfnet.onmqtt["th"](mqc, mqttTargTopic, "60" )
  nwfnet.onmqtt["th"](mqc, mqttModeTopic, "off")
  nwfnet.onmqtt["th"](mqc, mqttFanTopic , "on" )

Hardware
########

Peripheral Setup
================

+------+----+-----------------------------------------------------------+
| GPIO | IX |                                                           | 
+======+====+===========================================================+
|  16  |  0 | not used but somewhat special; "XPD"                      |
+------+----+-----------------------------------------------------------+
|  5   |  1 | 1-Wire                                                    |
+------+----+-----------------------------------------------------------+
|  4   |  2 | I2C SDA                                                   |
+------+----+-----------------------------------------------------------+
|  0   |  3 | I2C SCL / pull 0 for bootloader / bounce low to stop init |
+------+----+-----------------------------------------------------------+
|  2   |  4 | WS2812, by necessity of hardware                          |
+------+----+-----------------------------------------------------------+
|  14  |  5 | not used, but reserved for PCF IRQ                        |
+------+----+-----------------------------------------------------------+
|  12  |  6 | not used                                                  |
+------+----+-----------------------------------------------------------+
|  13  |  7 | not used                                                  |
+------+----+-----------------------------------------------------------+
|  15  |  8 | Pull low to select boot mode                              |
+------+----+-----------------------------------------------------------+

.. note::

   * GPIO2 (ix 4) is also the onboard LED
   * GPIOs 1,3 (ixes 9,10) are used for serial UART
   * GPIOs 6-11 (incl. 9,10, ixes 11,12) are used in chatting with the flash chip

I2C Peripherals
---------------

We have a PCF8574A attached to us on the I2C bus at address 0x38.  Its IO
lines are used as follows:

+----+-------------------+
| P0 | Relay 1: Fan      |
+----+-------------------+
| P1 | Relay 2: AC       |
+----+-------------------+
| P2 | Relay 3: Heat     |
+----+-------------------+
| P3 | Relay 4: Em Heat  |
+----+-------------------+
| P4 |                   |
+----+-------------------+
| P5 |                   |
+----+-------------------+
| P6 |                   |
+----+-------------------+
| P7 |                   |
+----+-------------------+

1W Peripherals
--------------

We have a DS1820 temperature probe attached to the 1Wire bus.  This device
calls itself 1013878a02080098 in my case.

Internals
=========

RTC RAM Slots
-------------

* Slots 0  - 9   are used by the RTC itself
* Slots 10 - 20  are used by the RTC fifo for metadata
* Slots 21 - 31  are unused
* Slots 32 - 128 are used by the RTC fifo for its journal


