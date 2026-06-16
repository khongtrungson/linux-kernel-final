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
