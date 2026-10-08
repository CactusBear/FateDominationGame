/**************************************************************************/
/*  console_wrapper_windows.cpp                                           */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#include <windows.h>

#include <shlwapi.h>

#include <cstdlib>
#include <cwchar>

#ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
#define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x4
#endif

// Protect only this wrapper; Windows independently delivers events to the engine.
static BOOL WINAPI service_console_handler(DWORD event) {
	return event == CTRL_C_EVENT || event == CTRL_BREAK_EVENT;
}

int main(int argc, char *argv[]) {
	// Get executable name.
	WCHAR exe_name[32767] = {};
	DWORD exe_name_length = GetModuleFileNameW(nullptr, exe_name, 32767);
	if (!exe_name_length || exe_name_length >= 32767) {
		wprintf(L"GetModuleFileName failed, error %d\n", GetLastError());
		return -1;
	}

	// Get product name from the resources and set console title.
	DWORD ver_info_handle = 0;
	DWORD ver_info_size = GetFileVersionInfoSizeW(exe_name, &ver_info_handle);
	if (ver_info_size > 0) {
		LPBYTE ver_info = (LPBYTE)malloc(ver_info_size);
		if (ver_info) {
			if (GetFileVersionInfoW(exe_name, ver_info_handle, ver_info_size, ver_info)) {
				LPCWSTR text_ptr = nullptr;
				UINT text_size = 0;
				if (VerQueryValueW(ver_info, L"\\StringFileInfo\\040904b0\\ProductName", (void **)&text_ptr, &text_size) && (text_size > 0)) {
					SetConsoleTitleW(text_ptr);
				}
			}
			free(ver_info);
		}
	}

	// Enable virtual terminal sequences processing.
	HANDLE stdout_handle = GetStdHandle(STD_OUTPUT_HANDLE);
	DWORD out_mode = 0;
	GetConsoleMode(stdout_handle, &out_mode);
	out_mode |= ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
	SetConsoleMode(stdout_handle, out_mode);

	// Find main executable name and check if it exist.
	static PCWSTR exe_renames[] = {
		L".console.exe",
		L"_console.exe",
		L" console.exe",
		L"console.exe",
		nullptr,
	};

	bool rename_found = false;
	for (int i = 0; exe_renames[i]; i++) {
		PWSTR c = StrRStrIW(exe_name, nullptr, exe_renames[i]);
		if (c) {
			CopyMemory(c, L".exe", sizeof(WCHAR) * 5);
			rename_found = true;
			break;
		}
	}
	if (!rename_found) {
		wprintf(L"Invalid wrapper executable name.\n");
		return -1;
	}

	DWORD file_attrib = GetFileAttributesW(exe_name);
	if (file_attrib == INVALID_FILE_ATTRIBUTES || (file_attrib & FILE_ATTRIBUTE_DIRECTORY)) {
		wprintf(L"Main executable %ls not found.\n", exe_name);
		return -1;
	}

	// Fail before spawning if graceful console-event protection is unavailable.
	if (!SetConsoleCtrlHandler(service_console_handler, TRUE)) {
		wprintf(L"SetConsoleCtrlHandler failed, error %d\n", GetLastError());
		return -1;
	}

	// Start the main process.
	PROCESS_INFORMATION pi;
	ZeroMemory(&pi, sizeof(pi));

	STARTUPINFOW si;
	ZeroMemory(&si, sizeof(si));
	si.cb = sizeof(si);
	si.dwFlags = STARTF_USESTDHANDLES;
	si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
	si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
	si.hStdError = GetStdHandle(STD_ERROR_HANDLE);

	WCHAR new_command_line[32767];
	// Keep the original argument tail verbatim, including its quoting/escaping.
	if (_snwprintf_s(new_command_line, 32767, _TRUNCATE, L"\"%ls\" %ls", exe_name, PathGetArgsW(GetCommandLineW())) < 0) {
		wprintf(L"Command line exceeds the Windows limit.\n");
		return -1;
	}

	if (!CreateProcessW(exe_name, new_command_line, nullptr, nullptr, true, 0, nullptr, nullptr, &si, &pi)) {
		wprintf(L"CreateProcess failed, error %d\n", GetLastError());
		return -1;
	}

	CloseHandle(pi.hThread);

	// No job ownership, timeout, signal forwarding, or termination fallback.
	// Wait for the engine itself, not for independently surviving descendants.
	if (WaitForSingleObject(pi.hProcess, INFINITE) != WAIT_OBJECT_0) {
		wprintf(L"WaitForSingleObject failed, error %d\n", GetLastError());
		CloseHandle(pi.hProcess);
		return -1;
	}

	DWORD exit_code = 0;
	if (!GetExitCodeProcess(pi.hProcess, &exit_code)) {
		wprintf(L"GetExitCodeProcess failed, error %d\n", GetLastError());
		CloseHandle(pi.hProcess);
		return -1;
	}

	CloseHandle(pi.hProcess);

	return exit_code;
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
	return main(0, nullptr);
}
