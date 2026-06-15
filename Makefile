all:
	make -C socket all
	make -C kernel all

clean:
	make -C socket clean
	make -C kernel clean

load:
	sudo insmod kernel/my_kernel_api.ko

unload:
	sudo rmmod my_kernel_api

.PHONY: all clean load unload
