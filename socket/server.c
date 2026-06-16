#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <fcntl.h>
#include <time.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/sysinfo.h>
#include <ifaddrs.h>
#include "common.h"

// Hàm xử lý tín hiệu SIGCHLD để dọn dẹp tiến trình con zombie
void sigchld_handler(int sig) {
    (void)sig;
    int saved_errno = errno;
    while (waitpid(-1, NULL, WNOHANG) > 0) {
        // Dọn dẹp tất cả tiến trình con đã kết thúc
    }
    errno = saved_errno;
}

// Hàm thu thập thông tin giám sát hệ thống kết hợp Procfs và User Space
void get_system_info(char *response_buffer, size_t max_len) {
    char temp[4096];
    memset(temp, 0, sizeof(temp));
    size_t offset = 0;

    // 1. RAM / Procfs Kernel
    int proc_fd = open("/proc/my_kernel_api", O_RDONLY);
    if (proc_fd >= 0) {
        char kbuf[512];
        memset(kbuf, 0, sizeof(kbuf));
        ssize_t bytes_read = read(proc_fd, kbuf, sizeof(kbuf) - 1);
        close(proc_fd);
        if (bytes_read > 0) {
            while (bytes_read > 0 && (kbuf[bytes_read - 1] == '\n' || kbuf[bytes_read - 1] == '\r' || kbuf[bytes_read - 1] == ' ')) {
                kbuf[bytes_read - 1] = '\0';
                bytes_read--;
            }
            offset += snprintf(temp + offset, sizeof(temp) - offset, "=== RAM Info (Kernel) ===\n%s\n\n", kbuf);
        } else {
            proc_fd = -1;
        }
    }
    
    if (proc_fd < 0) {
        struct sysinfo info;
        if (sysinfo(&info) == 0) {
            unsigned long free_mem = (info.freeram * info.mem_unit) / 1024;
            unsigned long total_mem = (info.totalram * info.mem_unit) / 1024;
            offset += snprintf(temp + offset, sizeof(temp) - offset,
                               "=== RAM Info (User Space) ===\n"
                               "[WARNING: Kernel Module not loaded. Using User Space sysinfo()]\n"
                               "Free Memory: %lu KB / Total Memory: %lu KB\n\n",
                               free_mem, total_mem);
        } else {
            offset += snprintf(temp + offset, sizeof(temp) - offset,
                               "=== RAM Info ===\n"
                               "ERROR: Không thể lấy thông tin bộ nhớ\n\n");
        }
    }

    // 2. CPU Load
    FILE *load_f = fopen("/proc/loadavg", "r");
    if (load_f) {
        double load1, load5, load15;
        if (fscanf(load_f, "%lf %lf %lf", &load1, &load5, &load15) == 3) {
            offset += snprintf(temp + offset, sizeof(temp) - offset,
                               "=== CPU Load (1m, 5m, 15m) ===\n"
                               "%.2f, %.2f, %.2f\n\n",
                               load1, load5, load15);
        }
        fclose(load_f);
    }

    // 3. Network Interfaces & IP Addresses
    offset += snprintf(temp + offset, sizeof(temp) - offset, "=== Network Interfaces ===\n");
    
    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) == 0) {
        for (ifa = ifaddr; ifa != NULL; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == NULL) continue;
            if (ifa->ifa_addr->sa_family == AF_INET) {
                struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
                char ip_str[INET_ADDRSTRLEN];
                if (inet_ntop(AF_INET, &(sa->sin_addr), ip_str, INET_ADDRSTRLEN)) {
                    offset += snprintf(temp + offset, sizeof(temp) - offset,
                                       "Interface: %s | IP Address: %s\n",
                                       ifa->ifa_name, ip_str);
                }
            }
        }
        freeifaddrs(ifaddr);
    }
    offset += snprintf(temp + offset, sizeof(temp) - offset, "\n");

    // Network stats
    FILE *net_f = fopen("/proc/net/dev", "r");
    if (net_f) {
        char line[256];
        if (fgets(line, sizeof(line), net_f)) {}
        if (fgets(line, sizeof(line), net_f)) {}
        offset += snprintf(temp + offset, sizeof(temp) - offset, "=== Network Traffic (Bytes RX/TX) ===\n");
        while (fgets(line, sizeof(line), net_f)) {
            char ifname[32];
            unsigned long long rx_bytes = 0, tx_bytes = 0;
            char *colon = strchr(line, ':');
            if (colon) {
                *colon = '\0';
                char *name_ptr = line;
                while (*name_ptr == ' ' || *name_ptr == '\t') name_ptr++;
                strncpy(ifname, name_ptr, sizeof(ifname) - 1);
                ifname[sizeof(ifname) - 1] = '\0';
                
                unsigned long long dummy;
                if (sscanf(colon + 1, "%llu %llu %llu %llu %llu %llu %llu %llu %llu", 
                            &rx_bytes, &dummy, &dummy, &dummy, &dummy, &dummy, &dummy, &dummy, &tx_bytes) >= 9) {
                    offset += snprintf(temp + offset, sizeof(temp) - offset,
                                       "Interface: %s | RX: %llu bytes | TX: %llu bytes\n",
                                       ifname, rx_bytes, tx_bytes);
                }
            }
        }
        fclose(net_f);
    }

    strncpy(response_buffer, temp, max_len - 1);
    response_buffer[max_len - 1] = '\0';
}

// Hàm ghi nhật ký sự kiện sử dụng các cuộc gọi hệ thống cấp thấp POSIX (Low-level I/O)
void log_event(const char *client_ip, const char *command, const char *status) {
    int fd = open("server.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        perror("Lỗi mở file server.log để ghi nhật ký");
        return;
    }

    time_t rawtime;
    struct tm *timeinfo;
    char timestamp[20]; // Định dạng YYYY-MM-DD HH:MM:SS\0

    time(&rawtime);
    timeinfo = localtime(&rawtime);
    if (timeinfo == NULL) {
        perror("Lỗi lấy thời gian hệ thống");
        close(fd);
        return;
    }

    if (strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", timeinfo) == 0) {
        fprintf(stderr, "Lỗi định dạng thời gian\n");
        close(fd);
        return;
    }

    char log_line[BUFFER_SIZE + 100];
    int len = snprintf(log_line, sizeof(log_line), "[%s] [%s] [%s] [%s]\n", timestamp, client_ip, command, status);
    if (len < 0 || len >= (int)sizeof(log_line)) {
        fprintf(stderr, "Lỗi định dạng dòng nhật ký hoặc dòng nhật ký quá dài\n");
        close(fd);
        return;
    }

    // Ghi nguyên khối (atomic write) vào file để tránh chồng chéo luồng dữ liệu
    ssize_t bytes_written = write(fd, log_line, len);
    if (bytes_written < 0) {
        perror("Lỗi ghi dữ liệu vào server.log");
    } else if (bytes_written < len) {
        fprintf(stderr, "Lỗi ghi thiếu byte vào server.log\n");
    }

    if (close(fd) < 0) {
        perror("Lỗi đóng file server.log");
    }
}

int main(void) {
    // Bỏ qua tín hiệu SIGPIPE để tránh crash server khi client đột ngột ngắt kết nối
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        perror("Lỗi thiết lập bỏ qua SIGPIPE");
        return EXIT_FAILURE;
    }

    // Đăng ký xử lý tín hiệu SIGCHLD tránh zombie
    struct sigaction sa;
    sa.sa_handler = sigchld_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    if (sigaction(SIGCHLD, &sa, NULL) < 0) {
        perror("Lỗi thiết lập sigaction cho SIGCHLD");
        return EXIT_FAILURE;
    }

    int server_fd = -1;
    int client_fd = -1;
    struct sockaddr_in address;
    int opt = 1;

    // Khởi tạo socket TCP
    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("Lỗi tạo socket server");
        return EXIT_FAILURE;
    }

    // Thiết lập tùy chọn SO_REUSEADDR qua setsockopt trước khi bind
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) < 0) {
        perror("Lỗi setsockopt (SO_REUSEADDR)");
        goto cleanup;
    }

    // Thiết lập địa chỉ
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr(SERVER_IP);
    address.sin_port = htons(SERVER_PORT);

    // Gán (bind) địa chỉ cục bộ 127.0.0.1 và cổng 8888
    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("Lỗi bind");
        goto cleanup;
    }

    // Lắng nghe (listen) kết nối với hàng đợi là 5
    if (listen(server_fd, 5) < 0) {
        perror("Lỗi listen");
        goto cleanup;
    }

    printf("TCP Server đang lắng nghe trên %s:%d...\n", SERVER_IP, SERVER_PORT);

    // Vòng lặp chính chấp nhận kết nối tuần tự
    while (1) {
        struct sockaddr_in client_address;
        socklen_t client_addrlen = sizeof(client_address);

        client_fd = accept(server_fd, (struct sockaddr *)&client_address, &client_addrlen);
        if (client_fd < 0) {
            perror("Lỗi accept");
            continue;
        }

        char client_ip[INET_ADDRSTRLEN];
        if (inet_ntop(AF_INET, &client_address.sin_addr, client_ip, INET_ADDRSTRLEN) == NULL) {
            perror("Lỗi lấy IP của client");
            strcpy(client_ip, "Unknown");
        }
        int client_port = ntohs(client_address.sin_port);
        printf("Client kết nối thành công từ: %s:%d\n", client_ip, client_port);

        // Ghi log sự kiện kết nối thành công [TIMESTAMP] [CLIENT-IP] [CONNECT] [OK]
        log_event(client_ip, "CONNECT", "OK");

        // Vòng lặp con nhận dữ liệu từ client hiện tại
        char buffer[BUFFER_SIZE];
        while (1) {
            memset(buffer, 0, sizeof(buffer));
            ssize_t valread = recv(client_fd, buffer, sizeof(buffer) - 1, 0);
            if (valread < 0) {
                perror("Lỗi nhận dữ liệu từ client");
                break;
            } else if (valread == 0) {
                printf("Client đã đóng kết nối.\n");
                break;
            }

            // Đảm bảo kết thúc chuỗi null an toàn
            buffer[valread] = '\0';

            // Kiểm tra lệnh EXIT
            if (strncmp(buffer, CMD_EXIT, strlen(CMD_EXIT)) == 0) {
                printf("Nhận lệnh EXIT. Đóng kết nối với client.\n");
                
                // Ghi log sự kiện nhận lệnh EXIT thành công
                log_event(client_ip, CMD_EXIT, RESP_OK);

                char response[] = RESP_OK;
                // Gửi phản hồi OK kèm ký tự kết thúc chuỗi \0
                if (send(client_fd, response, sizeof(response), 0) < 0) {
                    perror("Lỗi gửi phản hồi OK");
                }
                break;
            } else if (strncmp(buffer, CMD_READ_LOG, strlen(CMD_READ_LOG)) == 0) {
                printf("Nhận lệnh READ_LOG từ client.\n");

                int fd = open("server.log", O_RDONLY);
                if (fd < 0) {
                    char err_response[] = "ERROR:Không thể mở tệp nhật ký";
                    if (send(client_fd, err_response, sizeof(err_response), 0) < 0) {
                        perror("Lỗi gửi phản hồi ERROR cho READ_LOG");
                    }
                    log_event(client_ip, CMD_READ_LOG, "ERROR");
                } else {
                    char ok_prefix[] = "OK:";
                    if (send(client_fd, ok_prefix, strlen(ok_prefix), 0) < 0) {
                        perror("Lỗi gửi tiền tố OK:");
                        close(fd);
                        log_event(client_ip, CMD_READ_LOG, "ERROR");
                        break;
                    }

                    char read_buf[BUFFER_SIZE];
                    ssize_t bytes_read;
                    int send_failed = 0;
                    while ((bytes_read = read(fd, read_buf, sizeof(read_buf))) > 0) {
                        if (send(client_fd, read_buf, bytes_read, 0) < 0) {
                            perror("Lỗi gửi dữ liệu log qua socket");
                            send_failed = 1;
                            break;
                        }
                    }

                    if (bytes_read < 0) {
                        perror("Lỗi đọc file server.log");
                    }

                    close(fd);

                    if (!send_failed) {
                        char end_char = '\0';
                        if (send(client_fd, &end_char, 1, 0) < 0) {
                            perror("Lỗi gửi ký tự kết thúc \\0");
                        }
                        log_event(client_ip, CMD_READ_LOG, "OK");
                    }
                }
            } else if (strncmp(buffer, CMD_RUN_CMD, strlen(CMD_RUN_CMD)) == 0) {
                char *command_str = buffer + strlen(CMD_RUN_CMD);
                printf("Nhận lệnh RUN_CMD từ client: %s\n", command_str);

                int pipefd[2];
                if (pipe(pipefd) < 0) {
                    perror("Lỗi tạo pipe");
                    char err_response[] = "ERROR:Không thể tạo đường ống IPC";
                    if (send(client_fd, err_response, sizeof(err_response), 0) < 0) {
                        perror("Lỗi gửi phản hồi ERROR");
                    }
                    log_event(client_ip, "RUN_CMD", "ERROR");
                } else {
                    pid_t pid = fork();
                    if (pid < 0) {
                        perror("Lỗi fork");
                        char err_response[] = "ERROR:Không thể fork tiến trình con";
                        if (send(client_fd, err_response, sizeof(err_response), 0) < 0) {
                            perror("Lỗi gửi phản hồi ERROR");
                        }
                        close(pipefd[0]);
                        close(pipefd[1]);
                        log_event(client_ip, "RUN_CMD", "ERROR");
                    } else if (pid == 0) {
                        // Tiến trình con (Worker Process)
                        close(pipefd[0]);
                        if (dup2(pipefd[1], STDOUT_FILENO) < 0 || dup2(pipefd[1], STDERR_FILENO) < 0) {
                            perror("Lỗi dup2");
                            _exit(127);
                        }
                        close(pipefd[1]);

                        char *args[] = {"sh", "-c", command_str, NULL};
                        execvp("/bin/sh", args);
                        perror("Lỗi execvp");
                        _exit(127);
                    } else {
                        // Tiến trình cha (Server chính)
                        close(pipefd[1]);

                        char ok_prefix[] = "OK:";
                        if (send(client_fd, ok_prefix, strlen(ok_prefix), 0) < 0) {
                            perror("Lỗi gửi tiền tố OK:");
                        }

                        char read_buf[BUFFER_SIZE];
                        ssize_t bytes_read;
                        int send_failed = 0;
                        while ((bytes_read = read(pipefd[0], read_buf, sizeof(read_buf))) > 0) {
                            if (send(client_fd, read_buf, bytes_read, 0) < 0) {
                                perror("Lỗi gửi dữ liệu log qua socket");
                                send_failed = 1;
                                break;
                            }
                        }

                        if (bytes_read < 0) {
                            perror("Lỗi đọc dữ liệu từ pipe");
                        }

                        close(pipefd[0]);

                        if (!send_failed) {
                            char end_char = '\0';
                            if (send(client_fd, &end_char, 1, 0) < 0) {
                                perror("Lỗi gửi ký tự kết thúc \\0");
                            }
                            log_event(client_ip, "RUN_CMD", "OK");
                        }
                    }
                }
            } else if (strcmp(buffer, CMD_GET_SYS_INFO) == 0) {
                printf("Nhận lệnh GET_SYS_INFO từ client.\n");

                char *info_buf = malloc(4096);
                if (info_buf == NULL) {
                    char err_response[] = "ERROR:Không thể cấp phát bộ nhớ";
                    if (send(client_fd, err_response, sizeof(err_response), 0) < 0) {
                        perror("Lỗi gửi phản hồi ERROR");
                    }
                    log_event(client_ip, "GET_SYS_INFO", "ERROR");
                } else {
                    get_system_info(info_buf, 4096);

                    char ok_prefix[] = "OK:";
                    if (send(client_fd, ok_prefix, strlen(ok_prefix), 0) < 0) {
                        perror("Lỗi gửi tiền tố OK:");
                    }

                    if (send(client_fd, info_buf, strlen(info_buf), 0) < 0) {
                        perror("Lỗi gửi thông tin hệ thống");
                    }

                    char end_char = '\0';
                    if (send(client_fd, &end_char, 1, 0) < 0) {
                        perror("Lỗi gửi ký tự kết thúc \\0");
                    }

                    free(info_buf);
                    log_event(client_ip, "GET_SYS_INFO", "OK");
                }
            } else {
                // Ghi log sự kiện nhận lệnh không hợp lệ (ERROR)
                log_event(client_ip, buffer, RESP_ERROR);

                char response[] = RESP_ERROR;
                if (send(client_fd, response, sizeof(response), 0) < 0) {
                    perror("Lỗi gửi phản hồi ERROR");
                }
            }
        }

        close(client_fd);
        client_fd = -1;
    }

    close(server_fd);
    return EXIT_SUCCESS;

cleanup:
    if (client_fd >= 0) {
        close(client_fd);
    }
    if (server_fd >= 0) {
        close(server_fd);
    }
    return EXIT_FAILURE;
}
