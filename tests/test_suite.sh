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

# Khai báo các biến trạng thái để dọn dẹp tài nguyên
SERVER_PID=""

# Hàm in kết quả kiểm thử dạng màu sắc
print_ok() {
    local msg=$1
    echo -e "[\e[32m  OK  \e[0m] ${msg}"
}

print_fail() {
    local msg=$1
    echo -e "[\e[31m FAIL \e[0m] ${msg}"
}

# Hàm dọn dẹp giải phóng tài nguyên (Teardown)
cleanup() {
    echo -e "\n--- GIAI ĐOẠN DỌN DẸP (Teardown) ---"
    
    # Tắt tiến trình TCP Server ngầm nếu còn chạy
    if [ -n "${SERVER_PID}" ]; then
        if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
            echo "Đang tắt TCP Server (PID: ${SERVER_PID})..."
            kill -15 "${SERVER_PID}" >/dev/null 2>&1
            wait "${SERVER_PID}" >/dev/null 2>&1
        fi
    fi

    # Gỡ bỏ Kernel Module nếu đang nạp
    if lsmod | grep -q "my_kernel_api"; then
        echo "Đang gỡ bỏ Kernel Module (my_kernel_api)..."
        rmmod my_kernel_api >/dev/null 2>&1
    fi

    # Chạy làm sạch thư mục
    echo "Đang dọn dẹp các tệp trung gian biên dịch..."
    make -C "${ROOT_DIR}" clean > /dev/null 2>&1
    
    echo "Dọn dẹp hoàn tất."
}

# Đăng ký hàm dọn dẹp khi script kết thúc hoặc bị ngắt
trap cleanup EXIT SIGINT SIGTERM

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ] && [ "${IGNORE_ROOT_CHECK}" != "1" ]; then
    print_fail "Script phải được chạy với quyền root (sudo ./tests/test_suite.sh)."
    exit 1
fi

# 2. Kiểm tra cấu trúc thư mục
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

# 3. Kiểm tra các file khung
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

    if [ -x "${FILE_SYSTEM_TOOL}" ]; then
         print_ok "Quyền thực thi của $(basename "${FILE_SYSTEM_TOOL}") chính xác"
    else
         print_fail "Không có quyền thực thi cho $(basename "${FILE_SYSTEM_TOOL}")"
         success=1
    fi
    return "${success}"
}

# 4. Kiểm tra làm sạch (make clean) trước khi build
check_clean_before() {
    echo "--- GIAI ĐOẠN 3: Làm sạch trước khi biên dịch ---"
    make -C "${ROOT_DIR}" clean > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        print_ok "Làm sạch thư mục thành công trước khi biên dịch"
        return 0
    else
        print_fail "Lệnh làm sạch thất bại"
        return 1
    fi
}

# 5. Kiểm tra biên dịch (Make All)
check_build() {
    local success=0
    echo "--- GIAI ĐOẠN 4: Kiểm tra quy trình biên dịch (make all) ---"
    make -C "${ROOT_DIR}" all > /dev/null 2>&1
    local make_status=$?

    if [ "${make_status}" -eq 0 ]; then
        print_ok "Lệnh make all chạy thành công không có lỗi biên dịch"
    else
        print_fail "Lệnh make all thất bại với mã lỗi ${make_status}"
        return 1
    fi

    if [ -f "${DIR_SOCKET}/server" ] && [ -f "${DIR_SOCKET}/client" ] && [ -f "${DIR_KERNEL}/my_kernel_api.ko" ]; then
        print_ok "Tạo thành công toàn bộ các file nhị phân và tệp module nhân"
    else
        print_fail "Thiếu một hoặc nhiều tệp đầu ra sau biên dịch"
        success=1
    fi
    return "${success}"
}

# 6. Kiểm tra nạp Kernel Module & thao tác trực tiếp procfs
check_kernel_module() {
    echo "--- GIAI ĐOẠN 5: Kiểm tra nạp Kernel Module & Procfs ---"
    if [ "$EUID" -eq 0 ]; then
        insmod "${DIR_KERNEL}/my_kernel_api.ko"
        if [ $? -ne 0 ]; then
            print_fail "Nạp Kernel Module thất bại"
            return 1
        fi
        
        if [ ! -f /proc/my_kernel_api ]; then
            print_fail "Tệp ảo /proc/my_kernel_api không tự động được tạo"
            return 1
        fi
        print_ok "Nạp module nhân và tạo tệp ảo /proc/my_kernel_api thành công"

        # Ghi và đọc lại trực tiếp
        echo "TEST_SUITE_API_MSG" > /proc/my_kernel_api
        local proc_resp=$(cat /proc/my_kernel_api)
        if echo "${proc_resp}" | grep -q "\[Kernel Received\]: TEST_SUITE_API_MSG" && echo "${proc_resp}" | grep -q "\[Free Memory\]:"; then
            print_ok "Đọc/ghi trực tiếp vào tệp ảo /proc/my_kernel_api thành công đúng định dạng"
        else
            print_fail "Đọc/ghi trực tiếp vào tệp ảo phản hồi sai: ${proc_resp}"
            return 1
        fi
    else
        print_ok "[MOCK] Bỏ qua nạp module thực tế do không phải quyền root"
    fi
    return 0
}

# 7. Khởi chạy Server và giao tiếp qua Socket
check_socket_communication() {
    local success=0
    echo "--- GIAI ĐOẠN 6: Khởi chạy Server và kiểm tra giao tiếp socket ---"

    # Chạy server ở chế độ ngầm (background)
    (cd "${DIR_SOCKET}" && ./server > "${DIR_TESTS}/server_test.log" 2>&1) &
    SERVER_PID=$!
    sleep 1

    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
        print_fail "TCP Server không khởi động thành công"
        return 1
    fi
    print_ok "TCP Server khởi chạy thành công (PID: ${SERVER_PID})"

    # Kiểm tra lệnh GET_SYS_INFO khi module đã được nạp
    if [ "$EUID" -eq 0 ]; then
        local client_resp=$("${DIR_SOCKET}/client" "GET_SYS_INFO")
        if echo "${client_resp}" | grep -q "\[Kernel Received\]: TEST_SUITE_API_MSG" && echo "${client_resp}" | grep -q "\[Free Memory\]:"; then
            print_ok "Giao tiếp Socket thành công: Nhận thông số đúng từ Kernel Module"
        else
            print_fail "Lệnh GET_SYS_INFO phản hồi sai: ${client_resp}"
            success=1
        fi
    else
        print_ok "[MOCK] Bỏ qua kiểm tra GET_SYS_INFO thực tế với Kernel Module"
    fi

    # Kiểm tra lệnh RUN_CMD
    local cmd_resp=$("${DIR_SOCKET}/client" "RUN_CMD echo TEST_RUN")
    if echo "${cmd_resp}" | grep -q "TEST_RUN"; then
        print_ok "Giao tiếp Socket thành công: Thực thi lệnh hệ thống từ xa chính xác"
    else
        print_fail "Lệnh RUN_CMD phản hồi sai: ${cmd_resp}"
        success=1
    fi

    # Kiểm tra lệnh READ_LOG
    local log_resp=$("${DIR_SOCKET}/client" "READ_LOG")
    if echo "${log_resp}" | grep -q "GET_SYS_INFO" || echo "${log_resp}" | grep -q "RUN_CMD"; then
        print_ok "Giao tiếp Socket thành công: Đọc file nhật ký từ xa chính xác"
    else
        print_fail "Lệnh READ_LOG phản hồi sai: ${log_resp}"
        success=1
    fi

    return "${success}"
}

# 8. Kiểm tra hành vi Fallback khi gỡ module
check_fallback_behavior() {
    echo "--- GIAI ĐOẠN 7: Kiểm tra cơ chế Fallback khi chưa nạp Kernel Module ---"
    
    if [ "$EUID" -eq 0 ]; then
        rmmod my_kernel_api
        if [ -f /proc/my_kernel_api ]; then
            print_fail "Tệp ảo /proc/my_kernel_api chưa biến mất sau khi gỡ module"
            return 1
        fi
        print_ok "Gỡ module nhân thành công"
    else
        print_ok "[MOCK] Bỏ qua gỡ module thực tế"
    fi

    # Kiểm tra xem Server tự động fallback sang User Space khi gọi GET_SYS_INFO
    local client_resp=$("${DIR_SOCKET}/client" "GET_SYS_INFO")
    if echo "${client_resp}" | grep -q "\[WARNING: Kernel Module not loaded. Using User Space sysinfo()\]" && echo "${client_resp}" | grep -q "Free Memory:"; then
        print_ok "Cơ chế Fallback hoạt động đúng: Server cảnh báo và dùng thông tin RAM User Space"
    else
        print_fail "Cơ chế Fallback lỗi hoặc không trả về cảnh báo đúng: ${client_resp}"
        return 1
    fi
    return 0
}

# 9. Kiểm tra tiến trình zombie
check_zombies() {
    echo "--- GIAI ĐOẠN 8: Kiểm tra tiến trình Zombie ---"
    local zombie_count=$(ps -eo state | grep -c "Z")
    if [ "${zombie_count}" -eq 0 ]; then
        print_ok "Không phát hiện tiến trình zombie nào liên quan (zombie count = 0)"
        return 0
    else
        print_fail "Phát hiện có ${zombie_count} tiến trình zombie đang chạy"
        return 1
    fi
}

# Điều phối toàn bộ quy trình kiểm thử
main() {
    local exit_code=0

    check_directories
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_files
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_clean_before
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_build
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_kernel_module
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_socket_communication
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_fallback_behavior
    if [ $? -ne 0 ]; then exit_code=1; fi

    check_zombies
    if [ $? -ne 0 ]; then exit_code=1; fi

    # Tắt TCP Server an toàn qua lệnh EXIT
    "${DIR_SOCKET}/client" "EXIT" >/dev/null 2>&1
    sleep 0.5
    SERVER_PID="" # Hủy PID để cleanup trap không gửi tín hiệu kill lần nữa

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
