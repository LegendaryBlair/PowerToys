#pragma warning(push)
#pragma warning(disable : 26466)
#include "CppUnitTest.h"
#pragma warning(pop)

#include <windows.h>

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include "FileConversionEngine.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

namespace FileConverterLibUnitTests
{
    namespace
    {
        class FileCleanup
        {
        public:
            ~FileCleanup()
            {
                for (const auto& path : m_paths)
                {
                    std::error_code error;
                    std::filesystem::remove(path, error);
                }
            }

            std::filesystem::path Add(std::wstring_view name)
            {
                auto path = std::filesystem::current_path() /
                            (L"FileConverterUnitTest_" + std::to_wstring(GetCurrentProcessId()) + L"_" + std::wstring{ name });
                std::error_code error;
                std::filesystem::remove(path, error);
                m_paths.push_back(path);
                return path;
            }

        private:
            std::vector<std::filesystem::path> m_paths;
        };

        void WriteBmp(const std::filesystem::path& path, bool include_pixels)
        {
            constexpr DWORD width = 2;
            constexpr DWORD height = 2;
            constexpr DWORD image_size = 16;

            BITMAPFILEHEADER file_header{};
            file_header.bfType = 0x4D42;
            file_header.bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
            file_header.bfSize = file_header.bfOffBits + image_size;

            BITMAPINFOHEADER info_header{};
            info_header.biSize = sizeof(BITMAPINFOHEADER);
            info_header.biWidth = width;
            info_header.biHeight = height;
            info_header.biPlanes = 1;
            info_header.biBitCount = 24;
            info_header.biCompression = BI_RGB;
            info_header.biSizeImage = image_size;

            std::ofstream stream(path, std::ios::binary | std::ios::trunc);
            stream.write(reinterpret_cast<const char*>(&file_header), sizeof(file_header));
            stream.write(reinterpret_cast<const char*>(&info_header), sizeof(info_header));
            if (include_pixels)
            {
                constexpr unsigned char pixels[image_size] = {
                    0, 0, 255, 0, 255, 0, 0, 0,
                    255, 0, 0, 255, 255, 255, 0, 0,
                };
                stream.write(reinterpret_cast<const char*>(pixels), sizeof(pixels));
            }
        }
    }

    TEST_CLASS(FileConversionEngineTests)
    {
    public:
        TEST_METHOD(PngEncoderIsAvailable)
        {
            const auto result = file_converter::IsOutputFormatSupported(file_converter::ImageFormat::Png);

            Assert::IsTrue(result.succeeded(), result.error_message.c_str());
        }

        TEST_METHOD(ConvertBmpToPngCreatesOutput)
        {
            FileCleanup cleanup;
            const auto input_path = cleanup.Add(L"valid.bmp");
            const auto output_path = cleanup.Add(L"valid.png");
            WriteBmp(input_path, true);

            const auto result = file_converter::ConvertImageFile(
                input_path.wstring(),
                output_path.wstring(),
                file_converter::ImageFormat::Png);

            Assert::IsTrue(result.succeeded(), result.error_message.c_str());
            Assert::IsTrue(std::filesystem::exists(output_path));
            Assert::IsTrue(std::filesystem::file_size(output_path) > 0);
        }

        TEST_METHOD(UnsupportedInputDoesNotCreateOutput)
        {
            FileCleanup cleanup;
            const auto input_path = cleanup.Add(L"unsupported.png");
            const auto output_path = cleanup.Add(L"unsupported-output.png");
            std::ofstream{ input_path, std::ios::binary | std::ios::trunc } << "not an image";

            const auto result = file_converter::ConvertImageFile(
                input_path.wstring(),
                output_path.wstring(),
                file_converter::ImageFormat::Png);

            Assert::IsFalse(result.succeeded());
            Assert::IsFalse(std::filesystem::exists(output_path));
        }

        TEST_METHOD(TruncatedInputDoesNotLeavePartialOutput)
        {
            FileCleanup cleanup;
            const auto input_path = cleanup.Add(L"truncated.bmp");
            const auto output_path = cleanup.Add(L"truncated-output.png");
            WriteBmp(input_path, false);

            const auto result = file_converter::ConvertImageFile(
                input_path.wstring(),
                output_path.wstring(),
                file_converter::ImageFormat::Png);

            Assert::IsFalse(result.succeeded());
            Assert::IsFalse(std::filesystem::exists(output_path));
        }
    };
}
