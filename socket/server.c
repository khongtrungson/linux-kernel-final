#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include "common.h"

int main(void) {
    // Bỏ qua tín hiệu SIGPIPE để tránh crash server khi client đột ngột ngắt kết nối
    if (signal(SIGPIPE, SIG_IGN) == SIG_ERR) {
        perror("Lỗi thiết lập bỏ qua SIGPIPE");
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
                
                char response[] = RESP_OK;
                // Gửi phản hồi OK kèm ký tự kết thúc chuỗi \0
                if (send(client_fd, response, sizeof(response), 0) < 0) {
                    perror("Lỗi gửi phản hồi OK");
                }
                break;
            } else {
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
