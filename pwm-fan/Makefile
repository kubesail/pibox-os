CC = gcc
RM = rm -f

CFLAGS  = -Wall
LIBS    = -lbcm2835

TARGET = pi_fan_hwpwm

all: $(TARGET)

$(TARGET): $(TARGET).c
	$(CC) $(CFLAGS) -o $(TARGET) $(TARGET).c $(LIBS)

install: $(TARGET)
	install $(TARGET) /usr/local/sbin
	cp $(TARGET).service /etc/systemd/system/
	systemctl enable $(TARGET)
	! systemctl is-active --quiet $(TARGET) || systemctl stop $(TARGET)
	systemctl start $(TARGET)

uninstall: clean
	systemctl stop $(TARGET)
	systemctl disable $(TARGET)
	$(RM) /usr/local/sbin/$(TARGET)
	$(RM) /etc/systemd/system/$(TARGET).service
	$(RM) /run/$(TARGET).*
	@echo
	@echo "To remove the source directory"
	@echo "    $$ cd && rm -rf ${CURDIR}"
	@echo

clean:
	$(RM) $(TARGET)
