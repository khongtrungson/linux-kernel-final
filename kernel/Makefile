obj-m += my_kernel_api.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(CURDIR) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(CURDIR) clean

load:
	sudo insmod my_kernel_api.ko

unload:
	sudo rmmod my_kernel_api

.PHONY: all clean load unload
