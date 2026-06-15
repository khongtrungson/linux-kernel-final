#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Trungson");
MODULE_DESCRIPTION("linux-kernel-final Giao dien ao procfs");
MODULE_VERSION("1.0");

static int __init my_kernel_api_init(void) {
    printk(KERN_INFO "my_kernel_api: Module da duoc nap thanh cong!\n");
    return 0;
}

static void __exit my_kernel_api_exit(void) {
    printk(KERN_INFO "my_kernel_api: Module da duoc go bo sach se!\n");
}

module_init(my_kernel_api_init);
module_exit(my_kernel_api_exit);
