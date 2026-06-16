#!/bin/bash

# ==============================================================================
# Script kiểm thử tích hợp (Test Suite) cho linux-kernel-final
# Đảm bảo kiểm tra cấu trúc thư mục, biên dịch và hoạt động cơ bản của hệ thống.
# ==============================================================================

# Khai báo các đường dẫn thư mục và file cấu hình
readonly ROOT_DIR="/home/trungson/Desktop/linux-kernel-final"
readonly DIR_SHELL="${ROOT_DIR}/shell"
readonly DIR_SOCKET="${ROOT_DIR}/socket"
readonly DIR_KERNEL="${ROOT_DIR}/kernel"
readonly DIR_TESTS="${ROOT_DIR}/tests"

# Các file cần kiểm tra
readonly FILE_SYSTEM_TOOL="${DIR_SHELL}/system_tool.sh"
readonly FILE_SERVER="${DIR_SOCKET}/server.c"
readonly FILE_CLIENT="${DIR_SOCKET}/client.c"
readonly FILE_COMMON_H="${DIR_SOCKET}/common.h"
readonly FILE_MAKEFILE_SOCKET="${DIR_SOCKET}/Makefile"
readonly FILE_KERNEL_C="${DIR_KERNEL}/my_kernel_api.c"
readonly FILE_MAKEFILE_KERNEL="${DIR_KERNEL}/Makefile"
readonly FILE_MAKEFILE_ROOT="${ROOT_DIR}/Makefile"

# Hàm in kết quả kiểm thử dạng màu sắc
print_ok() {
    local msg=$1
    echo -e "[\e[32m  OK  \e[0m] ${msg}"
}

print_fail() {
    local msg=$1
    echo -e "[\e[31m FAIL \e[0m] ${msg}"
}

# 1. Kiểm tra cấu trúc thư mục
check_directories() {
    local success=0

    echo "--- GIAI ĐOẠN 1: Kiểm tra cấu trúc thư mục ---"
    
    for dir in "${DIR_SHELL}" "${DIR_SOCKET}" "${DIR_KERNEL}" "${DIR_TESTS}"; do
        if [ -d "${dir}" ]; then
            print_ok "Thư mục tồn tại: ${dir##*/}/"
        else
            print_fail "Thư mục thiếu: ${dir##*/}/"
            success=1
        fi
    done
    
    return "${success}"
}

# 2. Kiểm tra sự tồn tại của các file khung (Skeleton Files)
check_files() {
    local success=0

    echo "--- GIAI ĐOẠN 2: Kiểm tra các file khung ---"

    for file in "${FILE_SYSTEM_TOOL}" "${FILE_SERVER}" "${FILE_CLIENT}" "${FILE_COMMON_H}" \
                 "${FILE_MAKEFILE_SOCKET}" "${FILE_KERNEL_C}" "${FILE_MAKEFILE_KERNEL}" "${FILE_MAKEFILE_ROOT}"; do
        if [ -f "${file}" ]; then
            print_ok "File tồn tại: $(basename "${file}")"
        else
            print_fail "File thiếu: $(basename "${file}")"
            success=1
        fi
    done

    # Kiểm tra quyền thực thi của system_tool.sh
    if [ -x "${FILE_SYSTEM_TOOL}" ]; then
         print_ok "Quyền thực thi của $(basename "${FILE_SYSTEM_TOOL}") chính xác"
    else
         print_fail "Không có quyền thực thi cho $(basename "${FILE_SYSTEM_TOOL}")"
         success=1
    fi

    return "${success}"
}

# 3. Kiểm tra biên dịch (Make All)
check_build() {
    local success=0

    echo "--- GIAI ĐOẠN 3: Kiểm tra quy trình biên dịch ---"

    # Chạy make all từ thư mục gốc
    echo "Đang thực hiện biên dịch bằng lệnh: make all..."
    make -C "${ROOT_DIR}" all > /dev/null 2>&1
    local make_status=$?

    if [ "${make_status}" -eq 0 ]; then
        print_ok "Lệnh make all chạy thành công"
    else
        print_fail "Lệnh make all thất bại với mã lỗi ${make_status}"
        return 1
    fi

    # Kiểm tra các file nhị phân được tạo ra
    if [ -f "${DIR_SOCKET}/server" ]; then
        print_ok "File nhị phân server được tạo thành công"
    else
        print_fail "Thiếu file nhị phân server"
        success=1
    fi

    if [ -f "${DIR_SOCKET}/client" ]; then
        print_ok "File nhị phân client được tạo thành công"
    else
        print_fail "Thiếu file nhị phân client"
        success=1
    fi

    if [ -f "${DIR_KERNEL}/my_kernel_api.ko" ]; then
        print_ok "Linux Kernel Module (my_kernel_api.ko) được tạo thành công"
    else
        print_fail "Thiếu Linux Kernel Module (my_kernel_api.ko)"
        success=1
    fi

    return "${success}"
}

# 4. Kiểm tra làm sạch (Make Clean)
check_clean() {
    local success=0

    echo "--- GIAI ĐOẠN 4: Kiểm tra quy trình làm sạch (make clean) ---"

    # Chạy make clean từ thư mục gốc
    echo "Đang thực hiện dọn dẹp bằng lệnh: make clean..."
    make -C "${ROOT_DIR}" clean > /dev/null 2>&1
    local clean_status=$?

    if [ "${clean_status}" -eq 0 ]; then
         print_ok "Lệnh make clean chạy thành công"
    else
         print_fail "Lệnh make clean thất bại với mã lỗi ${clean_status}"
         return 1
    fi

    # Đảm bảo các file nhị phân và file tạm bị xóa sạch
    for file in "${DIR_SOCKET}/server" "${DIR_SOCKET}/client" "${DIR_KERNEL}/my_kernel_api.ko" \
                 "${DIR_KERNEL}/my_kernel_api.o" "${DIR_KERNEL}/my_kernel_api.mod" "${DIR_KERNEL}/my_kernel_api.mod.c"; do
        if [ -f "${file}" ]; then
            print_fail "File tạm/nhị phân chưa bị xóa sau make clean: $(basename "${file}")"
            success=1
        fi
    done

    if [ "${success}" -eq 0 ]; then
        print_ok "Toàn bộ file nhị phân và tệp trung gian đã được dọn sạch sẽ"
    fi

    return "${success}"
}

# Hàm kiểm tra tiến trình zombie
check_zombie_processes() {
    local zombie_count=$(ps -eo state | grep -c "Z")
    if [ "${zombie_count}" -eq 0 ]; then
        print_ok "Không có tiến trình zombie nào trong hệ thống (zombie count = 0)"
        return 0
    else
        print_fail "Phát hiện có ${zombie_count} tiến trình zombie"
        return 1
    fi
}

# 5. Kiểm tra giao tiếp Socket (Client - Server)
check_socket_communication() {
    local success=0
    echo "--- GIAI ĐOẠN 5: Kiểm tra giao tiếp Socket (Client - Server) ---"

    # Đảm bảo các binaries tồn tại
    if [ ! -f "${DIR_SOCKET}/server" ] || [ ! -f "${DIR_SOCKET}/client" ]; then
        print_fail "Thiếu file nhị phân server hoặc client. Không thể kiểm tra Socket."
        return 1
    fi

    # Chạy server ở chế độ ngầm (background) trong thư mục socket để log file sinh ra đúng chỗ
    (cd "${DIR_SOCKET}" && ./server > "${DIR_TESTS}/server_test.log" 2>&1) &
    local server_pid=$!

    # Chờ server khởi động và liên kết cổng
    sleep 0.5

    # Kiểm tra xem server có đang chạy không
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
        print_fail "TCP Server không hoạt động sau khi khởi chạy."
        return 1
    fi
    print_ok "TCP Server đã khởi chạy thành công (PID: ${server_pid})"

    # Kịch bản 1: Gửi lệnh thường HELLO và lệnh EXIT qua client
    echo -e "HELLO\nEXIT" | "${DIR_SOCKET}/client" > "${DIR_TESTS}/client_test1.log" 2>&1
    local client_status1=$?

    if [ "${client_status1}" -eq 0 ]; then
        print_ok "Client 1 đã trao đổi dữ liệu với Server và thoát sạch sẽ"
    else
        print_fail "Client 1 lỗi hoặc thoát với mã ${client_status1}"
        success=1
    fi

    # Kiểm tra phản hồi trong file log của client 1
    if grep -q "Phản hồi từ Server: ERROR" "${DIR_TESTS}/client_test1.log" && \
       grep -q "Phản hồi từ Server: OK" "${DIR_TESTS}/client_test1.log"; then
        print_ok "Nội dung phản hồi Client 1 chính xác (ERROR cho lệnh lạ, OK cho EXIT)"
    else
        print_fail "Phản hồi từ Server cho Client 1 không đúng chuẩn"
        success=1
    fi

    # Kịch bản 2: Kiểm tra Server vẫn tiếp tục lắng nghe sau khi Client 1 ngắt kết nối
    if ! kill -0 "${server_pid}" >/dev/null 2>&1; then
        print_fail "TCP Server đã bị sập/tắt sau khi Client 1 ngắt kết nối."
        success=1
    else
        print_ok "TCP Server vẫn hoạt động sau khi Client 1 thoát"

        # Khởi chạy client 2 để kiểm tra kết nối mới
        echo "EXIT" | "${DIR_SOCKET}/client" > "${DIR_TESTS}/client_test2.log" 2>&1
        local client_status2=$?

        if [ "${client_status2}" -eq 0 ] && grep -q "Phản hồi từ Server: OK" "${DIR_TESTS}/client_test2.log"; then
            print_ok "Client 2 kết nối, gửi lệnh EXIT và thoát thành công"
        else
            print_fail "Client 2 kết nối thất bại hoặc phản hồi không đúng"
            success=1
        fi
    fi

    # Dọn dẹp: Tắt server bằng SIGTERM và chờ nó kết thúc
    kill -15 "${server_pid}" >/dev/null 2>&1
    wait "${server_pid}" >/dev/null 2>&1

    # Kịch bản 3: Kiểm tra sự tồn tại và tính hợp lệ của server.log
    local log_file="${DIR_SOCKET}/server.log"
    if [ -f "${log_file}" ]; then
        print_ok "File server.log đã được tạo thành công"
        
        # Kiểm tra quyền 0644
        local perm=$(stat -c "%a" "${log_file}")
        if [ "${perm}" = "644" ]; then
            print_ok "Quyền file server.log chính xác (0644)"
        else
            print_fail "Quyền file server.log không đúng: ${perm} (kỳ vọng 0644)"
            success=1
        fi

        # Kiểm tra các dòng log định dạng TIMESTAMP, CLIENT-IP, COMMAND, STATUS
        # Dòng 1: [TIMESTAMP] [127.0.0.1] [CONNECT] [OK]
        if grep -q -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[127.0.0.1\] \[CONNECT\] \[OK\]$' "${log_file}"; then
            print_ok "Log CONNECT OK có định dạng chính xác"
        else
            print_fail "Không tìm thấy log CONNECT OK hoặc sai định dạng"
            success=1
        fi

        # Dòng 2: [TIMESTAMP] [127.0.0.1] [HELLO] [ERROR]
        if grep -q -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[127.0.0.1\] \[HELLO\] \[ERROR\]$' "${log_file}"; then
            print_ok "Log HELLO ERROR có định dạng chính xác"
        else
            print_fail "Không tìm thấy log HELLO ERROR hoặc sai định dạng"
            success=1
        fi

        # Dòng 3: [TIMESTAMP] [127.0.0.1] [EXIT] [OK]
        if grep -q -E '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[127.0.0.1\] \[EXIT\] \[OK\]$' "${log_file}"; then
            print_ok "Log EXIT OK có định dạng chính xác"
        else
            print_fail "Không tìm thấy log EXIT OK hoặc sai định dạng"
            success=1
        fi
    else
        print_fail "Không thấy file server.log được sinh ra."
        success=1
    fi

    # Xóa file log để đảm bảo kiểm thử sạch sẽ
    rm -f "${log_file}"

    # Kiểm tra tiến trình zombie
    check_zombie_processes
    if [ $? -ne 0 ]; then
        success=1
    fi

    # Xóa các file log tạm thời
    rm -f "${DIR_TESTS}/server_test.log" "${DIR_TESTS}/client_test1.log" "${DIR_TESTS}/client_test2.log"

    return "${success}"
}

# Điều phối toàn bộ quy trình kiểm thử
main() {
    local exit_code=0

    check_directories
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_files
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_build
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_socket_communication
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_clean
    if [ $? -ne 0 ]; then exit_code=1; fi

    echo "=============================================================================="
    if [ "${exit_code}" -eq 0 ]; then
        echo -e "\e[32mKẾT QUẢ: KIỂM THỬ THÀNH CÔNG (TẤT CẢ CÁC BƯỚC ĐỀU ĐẠT)\e[0m"
    else
        echo -e "\e[31mKẾT QUẢ: KIỂM THỬ THẤT BẠI (CÓ LỖI XẢY RA)\e[0m"
    fi
    echo "=============================================================================="

    exit "${exit_code}"
}

main
