#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/uaccess.h>
#include <linux/mutex.h>
#include <linux/mm.h>
#include <linux/sysinfo.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Trungson");
MODULE_DESCRIPTION("linux-kernel-final Giao dien ao procfs");
MODULE_VERSION("1.0");

static struct proc_dir_entry *proc_file;
static char kernel_buffer[1024];
static size_t kernel_buffer_len = 0;
static DEFINE_MUTEX(buffer_mutex);

static ssize_t my_proc_read(struct file *file, char __user *user_buf, size_t count, loff_t *ppos) {
    (void)file;
    char temp_buffer[1200];
    ssize_t len;
    struct sysinfo val;
    unsigned long free_ram_kb;
    
    if (*ppos > 0) {
        return 0;
    }
    
    if (mutex_lock_interruptible(&buffer_mutex)) {
        return -ERESTARTSYS;
    }
    
    si_meminfo(&val);
    free_ram_kb = (val.freeram * val.mem_unit) / 1024;
    
    len = snprintf(temp_buffer, sizeof(temp_buffer), "[Kernel Received]: %s | [Free Memory]: %lu KB\n", 
                   kernel_buffer, free_ram_kb);
    
    if (len < 0) {
        mutex_unlock(&buffer_mutex);
        return -EINVAL;
    }
    
    if (count < (size_t)len) {
        mutex_unlock(&buffer_mutex);
        return -EINVAL;
    }
    
    if (copy_to_user(user_buf, temp_buffer, len)) {
        mutex_unlock(&buffer_mutex);
        return -EFAULT;
    }
    
    *ppos = len;
    mutex_unlock(&buffer_mutex);
    return len;
}

static ssize_t my_proc_write(struct file *file, const char __user *user_buf, size_t count, loff_t *ppos) {
    (void)file;
    (void)ppos;
    
    if (count >= 1024) {
        return -EINVAL;
    }
    
    if (mutex_lock_interruptible(&buffer_mutex)) {
        return -ERESTARTSYS;
    }
    
    if (copy_from_user(kernel_buffer, user_buf, count)) {
        mutex_unlock(&buffer_mutex);
        return -EFAULT;
    }
    
    kernel_buffer[count] = '\0';
    kernel_buffer_len = count;
    
    if (kernel_buffer_len > 0 && kernel_buffer[kernel_buffer_len - 1] == '\n') {
        kernel_buffer[kernel_buffer_len - 1] = '\0';
        kernel_buffer_len--;
    }
    
    mutex_unlock(&buffer_mutex);
    return count;
}

static const struct proc_ops my_proc_ops = {
    .proc_read = my_proc_read,
    .proc_write = my_proc_write,
};

static int __init my_kernel_api_init(void) {
    proc_file = proc_create("my_kernel_api", 0666, NULL, &my_proc_ops);
    if (!proc_file) {
        printk(KERN_ERR "my_kernel_api: Khong the tao file ao /proc/my_kernel_api\n");
        return -ENOMEM;
    }
    printk(KERN_INFO "my_kernel_api: Module da duoc nap thanh cong!\n");
    return 0;
}

static void __exit my_kernel_api_exit(void) {
    proc_remove(proc_file);
    printk(KERN_INFO "my_kernel_api: Module da duoc go bo sach se!\n");
}

module_init(my_kernel_api_init);
module_exit(my_kernel_api_exit);
