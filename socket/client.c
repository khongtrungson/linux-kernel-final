#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "common.h"

int main(void) {
    int sock_fd = -1;
    struct sockaddr_in serv_addr;
    char buffer[BUFFER_SIZE];

    // Khởi tạo socket TCP
    sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("Lỗi tạo socket client");
        return EXIT_FAILURE;
    }

    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(SERVER_PORT);

    // Chuyển đổi địa chỉ IP từ chuỗi sang dạng nhị phân
    if (inet_pton(AF_INET, SERVER_IP, &serv_addr.sin_addr) <= 0) {
        perror("Địa chỉ IP máy chủ không hợp lệ");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    // Kết nối tới Server
    if (connect(sock_fd, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        perror("Kết nối tới máy chủ thất bại");
        close(sock_fd);
        return EXIT_FAILURE;
    }

    printf("Kết nối thành công tới máy chủ %s:%d\n", SERVER_IP, SERVER_PORT);

    // Chế độ nhận đầu vào từ bàn phím để gửi tới server
    while (1) {
        printf("Nhập lệnh: ");
        fflush(stdout);

        if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
            printf("\nNgắt kết nối từ bàn phím.\n");
            break;
        }

        // Loại bỏ ký tự xuống dòng (\n, \r)
        buffer[strcspn(buffer, "\r\n")] = '\0';

        // Bỏ qua nếu dòng trống
        if (strlen(buffer) == 0) {
            continue;
        }

        int is_exit = (strcmp(buffer, CMD_EXIT) == 0);

        // Gửi lệnh qua socket (bao gồm ký tự null kết thúc \0)
        ssize_t valsend = send(sock_fd, buffer, strlen(buffer) + 1, 0);
        if (valsend < 0) {
            perror("Lỗi gửi dữ liệu");
            break;
        }

        // Nhận phản hồi từ Server
        memset(buffer, 0, sizeof(buffer));
        ssize_t valread = recv(sock_fd, buffer, sizeof(buffer) - 1, 0);
        if (valread < 0) {
            perror("Lỗi nhận phản hồi");
            break;
        } else if (valread == 0) {
            printf("Máy chủ đã đóng kết nối.\n");
            break;
        }

        // Bảo đảm chuỗi phản hồi được kết thúc null
        buffer[valread] = '\0';
        printf("Phản hồi từ Server: %s\n", buffer);

        // Nếu lệnh là EXIT và nhận được phản hồi OK, đóng kết nối và thoát với mã 0
        if (is_exit && strcmp(buffer, RESP_OK) == 0) {
            printf("Đóng kết nối và thoát chương trình client.\n");
            close(sock_fd);
            return EXIT_SUCCESS;
        }
    }

    close(sock_fd);
    return EXIT_FAILURE;
}
