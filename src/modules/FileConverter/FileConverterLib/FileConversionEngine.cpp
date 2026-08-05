// Copyright (c) Microsoft Corporation
// Licensed under the MIT license.

#include "pch.h"

#include "FileConversionEngine.h"

#include <FileConverterResources.h>
#include <wrl/client.h>

#include <sstream>

extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace
{
    class OutputFileCleanup
    {
    public:
        explicit OutputFileCleanup(const std::wstring& path) :
            m_path(path)
        {
        }

        ~OutputFileCleanup()
        {
            if (m_armed)
            {
                DeleteFileW(m_path.c_str());
            }
        }

        void Arm()
        {
            m_armed = true;
        }

        void Release()
        {
            m_armed = false;
        }

    private:
        const std::wstring& m_path;
        bool m_armed = false;
    };

    std::wstring LoadLocalizedString(UINT resource_id, std::wstring_view fallback)
    {
        const wchar_t* value = nullptr;
        const int length = LoadStringW(
            reinterpret_cast<HMODULE>(&__ImageBase),
            resource_id,
            reinterpret_cast<wchar_t*>(&value),
            0);
        if (length > 0)
        {
            return std::wstring{ value, static_cast<size_t>(length) };
        }

        return std::wstring{ fallback };
    }

    std::wstring FormatLocalizedString(std::wstring format, std::wstring_view argument)
    {
        constexpr std::wstring_view placeholder = L"{0}";
        const size_t position = format.find(placeholder);
        if (position != std::wstring::npos)
        {
            format.replace(position, placeholder.size(), argument);
        }

        return format;
    }

    GUID ContainerFormatFor(file_converter::ImageFormat format)
    {
        switch (format)
        {
        case file_converter::ImageFormat::Jpeg:
            return GUID_ContainerFormatJpeg;
        case file_converter::ImageFormat::Bmp:
            return GUID_ContainerFormatBmp;
        case file_converter::ImageFormat::Tiff:
            return GUID_ContainerFormatTiff;
        case file_converter::ImageFormat::Heif:
            return GUID_ContainerFormatHeif;
        case file_converter::ImageFormat::Webp:
            return GUID_ContainerFormatWebp;
        case file_converter::ImageFormat::Png:
        default:
            return GUID_ContainerFormatPng;
        }
    }

    const wchar_t* ExtensionFor(file_converter::ImageFormat format)
    {
        switch (format)
        {
        case file_converter::ImageFormat::Jpeg:
            return L".jpg";
        case file_converter::ImageFormat::Bmp:
            return L".bmp";
        case file_converter::ImageFormat::Tiff:
            return L".tiff";
        case file_converter::ImageFormat::Heif:
            return L".heic";
        case file_converter::ImageFormat::Webp:
            return L".webp";
        case file_converter::ImageFormat::Png:
        default:
            return L".png";
        }
    }

    constexpr bool IsMissingCodecHresult(HRESULT hr) noexcept
    {
        return hr == WINCODEC_ERR_COMPONENTNOTFOUND ||
               hr == HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    }

    std::wstring HrMessage(std::wstring_view prefix, HRESULT hr)
    {
        std::wstringstream stream;
        stream << prefix << L" HRESULT=0x" << std::hex << std::uppercase << static_cast<unsigned long>(hr);
        return stream.str();
    }

    struct ScopedCom
    {
        HRESULT hr;
        bool uninitialize;

        ScopedCom()
            : hr(E_FAIL), uninitialize(false)
        {
            // Prefer MTA, but gracefully handle callers that already initialized
            // COM in a different apartment (e.g. Explorer STA threads).
            hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            if (hr == RPC_E_CHANGED_MODE)
            {
                hr = S_OK;
                return;
            }

            if (SUCCEEDED(hr))
            {
                uninitialize = true;
            }
        }

        ~ScopedCom()
        {
            if (uninitialize)
            {
                CoUninitialize();
            }
        }
    };

    HRESULT CreateWicFactory(Microsoft::WRL::ComPtr<IWICImagingFactory>& factory)
    {
        HRESULT hr = CoCreateInstance(CLSID_WICImagingFactory2, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
        if (FAILED(hr))
        {
            hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
        }

        return hr;
    }

    file_converter::ConversionResult EnsureOutputEncoderAvailable(IWICImagingFactory* factory, file_converter::ImageFormat format)
    {
        if (factory == nullptr)
        {
            return { E_POINTER, LoadLocalizedString(IDS_FILECONVERTER_ENGINE_WICFACTORYNULL, L"WIC factory is null.") };
        }

        Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder_probe;
        const HRESULT hr = factory->CreateEncoder(ContainerFormatFor(format), nullptr, &encoder_probe);
        if (FAILED(hr))
        {
            if (IsMissingCodecHresult(hr))
            {
                const std::wstring error = FormatLocalizedString(
                    LoadLocalizedString(IDS_FILECONVERTER_ENGINE_NOENCODERINSTALLED, L"No WIC encoder is installed for destination format '{0}'."),
                    ExtensionFor(format));
                return { HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED), error };
            }

            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATEENCODERFAILED, L"Failed creating image encoder."), hr) };
        }

        return { S_OK, L"" };
    }
}

namespace file_converter
{
    ConversionResult IsOutputFormatSupported(ImageFormat format)
    {
        ScopedCom com;
        if (FAILED(com.hr))
        {
            return { com.hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_COINITIALIZEFAILED, L"CoInitializeEx failed."), com.hr) };
        }

        Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
        const HRESULT hr = CreateWicFactory(factory);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATEWICFACTORYFAILED, L"Failed creating WIC factory."), hr) };
        }

        return EnsureOutputEncoderAvailable(factory.Get(), format);
    }

    ConversionResult ConvertImageFile(const std::wstring& input_path, const std::wstring& output_path, ImageFormat format)
    {
        ScopedCom com;
        if (FAILED(com.hr))
        {
            return { com.hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_COINITIALIZEFAILED, L"CoInitializeEx failed."), com.hr) };
        }

        Microsoft::WRL::ComPtr<IWICImagingFactory> factory;
        HRESULT hr = CreateWicFactory(factory);

        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATEWICFACTORYFAILED, L"Failed creating WIC factory."), hr) };
        }

        const auto output_support = EnsureOutputEncoderAvailable(factory.Get(), format);
        if (FAILED(output_support.hr))
        {
            return output_support;
        }

        Microsoft::WRL::ComPtr<IWICBitmapDecoder> decoder;
        hr = factory->CreateDecoderFromFilename(input_path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad, &decoder);
        if (FAILED(hr))
        {
            if (hr == WINCODEC_ERR_UNKNOWNIMAGEFORMAT || IsMissingCodecHresult(hr))
            {
                return { hr, LoadLocalizedString(IDS_FILECONVERTER_ENGINE_INPUTUNSUPPORTED, L"Input image format is not supported by installed WIC decoders.") };
            }

            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_OPENINPUTFAILED, L"Failed opening input image."), hr) };
        }

        Microsoft::WRL::ComPtr<IWICBitmapFrameDecode> source_frame;
        hr = decoder->GetFrame(0, &source_frame);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_READFIRSTFRAMEFAILED, L"Failed reading first image frame."), hr) };
        }

        UINT width = 0;
        UINT height = 0;
        hr = source_frame->GetSize(&width, &height);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_READIMAGESIZEFAILED, L"Failed reading image size."), hr) };
        }

        WICPixelFormatGUID pixel_format = {};
        hr = source_frame->GetPixelFormat(&pixel_format);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_READPIXELFORMATFAILED, L"Failed reading source pixel format."), hr) };
        }

        OutputFileCleanup output_cleanup(output_path);
        Microsoft::WRL::ComPtr<IWICStream> output_stream;
        hr = factory->CreateStream(&output_stream);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATESTREAMFAILED, L"Failed creating WIC stream."), hr) };
        }

        hr = output_stream->InitializeFromFilename(output_path.c_str(), GENERIC_WRITE);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_OPENOUTPUTFAILED, L"Failed opening output path."), hr) };
        }
        output_cleanup.Arm();

        Microsoft::WRL::ComPtr<IWICBitmapEncoder> encoder;
        hr = factory->CreateEncoder(ContainerFormatFor(format), nullptr, &encoder);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATEENCODERFAILED, L"Failed creating image encoder."), hr) };
        }

        hr = encoder->Initialize(output_stream.Get(), WICBitmapEncoderNoCache);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_INITENCODERFAILED, L"Failed initializing encoder."), hr) };
        }

        Microsoft::WRL::ComPtr<IWICBitmapFrameEncode> target_frame;
        Microsoft::WRL::ComPtr<IPropertyBag2> frame_properties;
        hr = encoder->CreateNewFrame(&target_frame, &frame_properties);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATETARGETFRAMEFAILED, L"Failed creating target frame."), hr) };
        }

        hr = target_frame->Initialize(frame_properties.Get());
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_INITTARGETFRAMEFAILED, L"Failed initializing target frame."), hr) };
        }

        hr = target_frame->SetSize(width, height);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_SETTARGETSIZEFAILED, L"Failed setting target size."), hr) };
        }

        WICPixelFormatGUID target_pixel_format = pixel_format;
        hr = target_frame->SetPixelFormat(&target_pixel_format);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_SETTARGETPIXELFORMATFAILED, L"Failed setting target pixel format."), hr) };
        }

        Microsoft::WRL::ComPtr<IWICBitmapSource> source_for_write = source_frame;
        Microsoft::WRL::ComPtr<IWICFormatConverter> format_converter;

        if (!InlineIsEqualGUID(pixel_format, target_pixel_format))
        {
            hr = factory->CreateFormatConverter(&format_converter);
            if (FAILED(hr))
            {
                return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_CREATEFORMATCONVERTERFAILED, L"Failed creating format converter."), hr) };
            }

            BOOL can_convert = FALSE;
            hr = format_converter->CanConvert(pixel_format, target_pixel_format, &can_convert);
            if (FAILED(hr) || !can_convert)
            {
                const HRESULT conversion_hr = FAILED(hr) ? hr : WINCODEC_ERR_UNSUPPORTEDPIXELFORMAT;
                return { conversion_hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_UNSUPPORTEDPIXELCONVERSION, L"Source pixel format cannot be converted to target pixel format."), conversion_hr) };
            }

            hr = format_converter->Initialize(source_frame.Get(), target_pixel_format, WICBitmapDitherTypeNone, nullptr, 0.0f, WICBitmapPaletteTypeCustom);
            if (FAILED(hr))
            {
                return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_INITFORMATCONVERTERFAILED, L"Failed initializing format converter."), hr) };
            }

            source_for_write = format_converter;
        }

        hr = target_frame->WriteSource(source_for_write.Get(), nullptr);
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_WRITETARGETFRAMEFAILED, L"Failed writing target frame."), hr) };
        }

        hr = target_frame->Commit();
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_COMMITTARGETFRAMEFAILED, L"Failed committing target frame."), hr) };
        }

        hr = encoder->Commit();
        if (FAILED(hr))
        {
            return { hr, HrMessage(LoadLocalizedString(IDS_FILECONVERTER_ENGINE_COMMITENCODERFAILED, L"Failed committing encoder."), hr) };
        }

        output_cleanup.Release();
        return { S_OK, L"" };
    }
}
