#!/bin/bash

# ==============================================================================
# Shell Tool - Giao diện dòng lệnh tương tác quản lý hệ thống
# Yêu cầu chạy bằng quyền root/sudo.
# ==============================================================================

# 1. Xác thực đặc quyền Root
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "${EUID}" -ne 0 ]; then
        echo "Lỗi: Vui lòng chạy bằng quyền root (sudo)!"
        exit 1
    fi
fi

# 2. Các hàm quản lý File
# Hàm hiển thị menu quản lý file
show_file_menu() {
    echo "-----------------------------------------"
    echo "          QUẢN LÝ FILE & THƯ MỤC         "
    echo "-----------------------------------------"
    echo "1. Tìm kiếm file/thư mục"
    echo "2. Tạo file/thư mục"
    echo "3. Xóa file/thư mục"
    echo "4. Sao chép file/thư mục"
    echo "5. Di chuyển file/thư mục"
    echo "6. Quay lại menu chính"
    echo "-----------------------------------------"
}

# Hàm tìm kiếm file
find_files() {
    local search_name search_dir
    read -p "Nhập tên tệp/thư mục cần tìm (hoặc một phần tên): " search_name
    read -p "Nhập thư mục bắt đầu tìm kiếm (mặc định là thư mục hiện tại): " search_dir
    
    # Nếu để trống thư mục tìm kiếm, mặc định là thư mục hiện tại
    if [ -z "${search_dir}" ]; then
        search_dir="."
    fi
    
    if [ ! -d "${search_dir}" ]; then
        echo "Lỗi: Thư mục '${search_dir}' không tồn tại!"
        return
    fi
    
    echo "Kết quả tìm kiếm cho '${search_name}' trong '${search_dir}':"
    find "${search_dir}" -name "*${search_name}*"
}

# Hàm tạo file hoặc thư mục
create_item() {
    local choice path
    echo "1. Tạo file trống"
    echo "2. Tạo thư mục"
    read -p "Lựa chọn của bạn (1-2): " choice
    
    case "${choice}" in
        1)
            read -p "Nhập đường dẫn file cần tạo: " path
            if [ -z "${path}" ]; then
                echo "Lỗi: Đường dẫn không được để trống!"
                return
            fi
            touch "${path}"
            if [ $? -eq 0 ]; then
                echo "Tạo file '${path}' thành công."
            else
                echo "Lỗi: Không thể tạo file '${path}'."
            fi
            ;;
        2)
            read -p "Nhập đường dẫn thư mục cần tạo: " path
            if [ -z "${path}" ]; then
                echo "Lỗi: Đường dẫn không được để trống!"
                return
            fi
            mkdir -p "${path}"
            if [ $? -eq 0 ]; then
                echo "Tạo thư mục '${path}' thành công."
            else
                echo "Lỗi: Không thể tạo thư mục '${path}'."
            fi
            ;;
        *)
            echo "Lựa chọn không hợp lệ."
            ;;
    esac
}

# Hàm xóa file hoặc thư mục
delete_item() {
    local path confirm
    read -p "Nhập đường dẫn file/thư mục cần xóa: " path
    
    if [ -z "${path}" ]; then
        echo "Lỗi: Đường dẫn không được để trống!"
        return
    fi
    
    if [ ! -e "${path}" ]; then
        echo "Lỗi: Đường dẫn '${path}' không tồn tại!"
        return
    fi
    
    read -p "Bạn có chắc chắn muốn xóa '${path}' không? (y/N): " confirm
    case "${confirm}" in
        [yY] | [yY][eE][sS])
            if [ -d "${path}" ]; then
                rm -rf "${path}"
            else
                rm -f "${path}"
            fi
            
            if [ $? -eq 0 ]; then
                echo "Xóa thành công '${path}'."
            else
                echo "Lỗi: Không thể xóa '${path}'."
            fi
            ;;
        *)
            echo "Đã hủy thao tác xóa."
            ;;
    esac
}

# Hàm sao chép file hoặc thư mục
copy_item() {
    local src dest
    read -p "Nhập đường dẫn nguồn: " src
    read -p "Nhập đường dẫn đích: " dest
    
    if [ -z "${src}" ] || [ -z "${dest}" ]; then
        echo "Lỗi: Đường dẫn nguồn và đích không được để trống!"
        return
    fi
    
    if [ ! -e "${src}" ]; then
        echo "Lỗi: Đường dẫn nguồn '${src}' không tồn tại!"
        return
    fi
    
    if [ -d "${src}" ]; then
        cp -r "${src}" "${dest}"
    else
        cp "${src}" "${dest}"
    fi
    
    if [ $? -eq 0 ]; then
        echo "Sao chép thành công từ '${src}' sang '${dest}'."
    else
        echo "Lỗi: Không thể sao chép."
    fi
}

# Hàm di chuyển file hoặc thư mục
move_item() {
    local src dest
    read -p "Nhập đường dẫn nguồn: " src
    read -p "Nhập đường dẫn đích: " dest
    
    if [ -z "${src}" ] || [ -z "${dest}" ]; then
        echo "Lỗi: Đường dẫn nguồn và đích không được để trống!"
        return
    fi
    
    if [ ! -e "${src}" ]; then
        echo "Lỗi: Đường dẫn nguồn '${src}' không tồn tại!"
        return
    fi
    
    mv "${src}" "${dest}"
    if [ $? -eq 0 ]; then
        echo "Di chuyển thành công từ '${src}' sang '${dest}'."
    else
        echo "Lỗi: Không thể di chuyển."
    fi
}

# Điều phối Menu con Quản lý file
handle_file_menu() {
    local choice
    while true; do
        show_file_menu
        read -p "Lựa chọn của bạn (1-6): " choice
        case "${choice}" in
            1)
                find_files
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            2)
                create_item
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                delete_item
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            4)
                copy_item
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            5)
                move_item
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            6)
                break
                ;;
            *)
                echo "Lỗi: Lựa chọn không hợp lệ! Vui lòng chọn từ 1 đến 6."
                read -p "Nhấn Enter để tiếp tục..."
                ;;
        esac
    done
}

# 3. Hàm lập lịch tác vụ tự động qua Crontab
schedule_task() {
    local path abs_path freq cron_expr confirm existing_jobs
    
    echo "-----------------------------------------"
    echo "            LẬP LỊCH TÁC VỤ            "
    echo "-----------------------------------------"
    read -p "Nhập đường dẫn tệp kịch bản cần lập lịch: " path
    
    if [ -z "${path}" ]; then
        echo "Lỗi: Đường dẫn không được để trống!"
        return
    fi
    
    if [ ! -f "${path}" ]; then
        echo "Lỗi: Tệp '${path}' không tồn tại!"
        return
    fi
    
    # Kiểm tra và cấp quyền thực thi nếu chưa có
    if [ ! -x "${path}" ]; then
        echo "Cảnh báo: Tệp '${path}' chưa có quyền thực thi."
        read -p "Bạn có muốn cấp quyền thực thi (chmod +x) cho tệp này không? (y/N): " confirm
        case "${confirm}" in
            [yY] | [yY][eE][sS])
                chmod +x "${path}"
                if [ $? -eq 0 ]; then
                    echo "Cấp quyền thực thi thành công."
                else
                    echo "Lỗi: Không thể cấp quyền thực thi!"
                    return
                fi
                ;;
            *)
                echo "Lỗi: Không thể lập lịch cho tệp không có quyền thực thi!"
                return
                ;;
        esac
    fi
    
    # Lấy đường dẫn tuyệt đối
    abs_path=$(realpath "${path}")
    
    # Lựa chọn tần suất lập lịch
    echo "Chọn chu kỳ chạy tác vụ:"
    echo "1. Hàng giờ (0 * * * *)"
    echo "2. Hàng ngày (0 0 * * *)"
    echo "3. Hàng tuần (0 0 * * 0)"
    echo "4. Hàng tháng (0 0 1 * *)"
    echo "5. Biểu thức cron tùy chỉnh"
    read -p "Lựa chọn của bạn (1-5): " freq
    
    case "${freq}" in
        1) cron_expr="0 * * * *" ;;
        2) cron_expr="0 0 * * *" ;;
        3) cron_expr="0 0 * * 0" ;;
        4) cron_expr="0 0 1 * *" ;;
        5)
            read -p "Nhập biểu thức cron (5 trường, ví dụ: */5 * * * *): " cron_expr
            if [ -z "${cron_expr}" ]; then
                echo "Lỗi: Biểu thức cron không được để trống!"
                return
            fi
            ;;
        *)
            echo "Lựa chọn không hợp lệ."
            return
            ;;
    esac
    
    # Kiểm tra xem cronjob đã tồn tại chưa
    if crontab -l 2>/dev/null | grep -Fq "${abs_path}"; then
        echo "Thông báo: Tác vụ này đã tồn tại trong danh sách crontab!"
        return
    fi
    
    # Đăng ký vào crontab
    existing_jobs=$(crontab -l 2>/dev/null)
    if [ -n "${existing_jobs}" ]; then
        (echo "${existing_jobs}"; echo "${cron_expr} ${abs_path}") | crontab -
    else
        echo "${cron_expr} ${abs_path}" | crontab -
    fi
    
    # Kiểm tra lại kết quả
    if crontab -l 2>/dev/null | grep -Fq "${abs_path}"; then
        echo "Đăng ký crontab thành công!"
        echo "Lệnh đã thêm: ${cron_expr} ${abs_path}"
    else
        echo "Lỗi: Đăng ký crontab thất bại!"
    fi
}

# 4. Hàm cấu hình thời gian hệ thống
set_system_time() {
    local datetime_str
    
    echo "-----------------------------------------"
    echo "         CẤU HÌNH GIỜ HỆ THỐNG          "
    echo "-----------------------------------------"
    read -p "Nhập chuỗi ngày giờ (định dạng YYYY-MM-DD HH:MM:SS): " datetime_str
    
    if [ -z "${datetime_str}" ]; then
        echo "Lỗi: Chuỗi ngày giờ không được để trống!"
        return
    fi
    
    # Kiểm tra định dạng bằng regex
    if [[ ! "${datetime_str}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
        echo "Lỗi: Ngày giờ nhập vào sai định dạng YYYY-MM-DD HH:MM:SS!"
        return
    fi
    
    # Kiểm tra tính hợp lệ logic của ngày giờ bằng date -d
    if ! date -d "${datetime_str}" &>/dev/null; then
        echo "Lỗi: Ngày giờ không hợp lệ!"
        return
    fi
    
    # Cập nhật thời gian hệ thống bằng date -s
    date -s "${datetime_str}" > /dev/null
    if [ $? -eq 0 ]; then
        echo "Cập nhật thời gian hệ thống thành công!"
        echo "Thời gian hiện tại: $(date '+%Y-%m-%d %H:%M:%S')"
    else
        echo "Lỗi: Không thể cập nhật thời gian hệ thống!"
    fi
}

# 4.5. Hàm quản lý phần mềm
manage_software() {
    local package_name confirm exit_code
    
    echo "-----------------------------------------"
    echo "            QUẢN LÝ PHẦN MỀM             "
    echo "-----------------------------------------"
    read -p "Nhập tên gói phần mềm cần quản lý: " package_name
    
    if [ -z "${package_name}" ]; then
        echo "Lỗi: Tên gói phần mềm không được để trống!"
        return 1
    fi
    
    # Xác thực tên gói bằng regex để tránh Command Injection hoặc lỗi cấu pháp
    if [[ ! "${package_name}" =~ ^[a-z0-9.+-]+$ ]]; then
        echo "Lỗi: Tên gói phần mềm không hợp lệ!"
        return 1
    fi
    
    # Kiểm tra trạng thái cài đặt sử dụng dpkg-query
    if dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q "ok installed"; then
        echo "Trạng thái: Gói '${package_name}' đã được cài đặt."
        read -p "Bạn có muốn gỡ bỏ gói này không? (y/N): " confirm
        case "${confirm}" in
            [yY] | [yY][eE][sS])
                echo "Đang gỡ bỏ gói '${package_name}'..."
                sudo apt-get remove -y "${package_name}"
                exit_code=$?
                if [ ${exit_code} -eq 0 ]; then
                    echo "Gỡ bỏ gói '${package_name}' thành công!"
                else
                    echo "Lỗi: Không thể gỡ bỏ gói '${package_name}'! (Mã lỗi: ${exit_code})"
                    echo "Gợi ý: Tiến trình APT có thể đang bận hoặc bị khóa bởi ứng dụng khác."
                    return 1
                fi
                ;;
            *)
                echo "Đã hủy thao tác gỡ bỏ."
                ;;
        esac
    else
        echo "Trạng thái: Gói '${package_name}' chưa được cài đặt."
        read -p "Bạn có muốn cài đặt gói này không? (y/N): " confirm
        case "${confirm}" in
            [yY] | [yY][eE][sS])
                echo "Đang cài đặt gói '${package_name}'..."
                sudo apt-get install -y "${package_name}"
                exit_code=$?
                if [ ${exit_code} -eq 0 ]; then
                    echo "Cài đặt gói '${package_name}' thành công!"
                else
                    echo "Lỗi: Không thể cài đặt gói '${package_name}'! (Mã lỗi: ${exit_code})"
                    echo "Gợi ý: Vui lòng kiểm tra kết nối mạng hoặc xem tiến trình APT khác có đang chạy hay không."
                    return 1
                fi
                ;;
            *)
                echo "Đã hủy thao tác cài đặt."
                ;;
        esac
    fi
    return 0
}

# 5. Hàm hiển thị menu chính
show_menu() {
    echo "========================================="
    echo "  MENU QUẢN TRỊ HỆ THỐNG (SHELL TOOL)  "
    echo "========================================="
    echo "1. Quản lý File"
    echo "2. Lập lịch Tác vụ"
    echo "3. Cấu hình Giờ Hệ thống"
    echo "4. Quản lý Phần mềm"
    echo "5. Thoát"
    echo "========================================="
}

# 6. Vòng lặp tương tác chính
main_loop() {
    local choice
    while true; do
        show_menu
        read -p "Vui lòng chọn một tính năng (1-5): " choice
        case "${choice}" in
            1)
                handle_file_menu
                ;;
            2)
                schedule_task
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                set_system_time
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            4)
                manage_software
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            5)
                echo "Cảm ơn bạn đã sử dụng Shell Tool. Tạm biệt!"
                exit 0
                ;;
            *)
                echo "Lỗi: Lựa chọn không hợp lệ! Vui lòng chọn từ 1 đến 5."
                read -p "Nhấn Enter để tiếp tục..."
                ;;
        esac
    done
}

# Khởi chạy vòng lặp chính
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_loop
fi



