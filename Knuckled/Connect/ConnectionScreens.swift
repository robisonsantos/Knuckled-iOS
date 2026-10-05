import SwiftUI
import KnuckledCore

struct HostingView: View {
    let pin: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("Pairing code")
                    .font(.headline)
                    .foregroundStyle(AppColors.ivory)
                HStack(spacing: 8) {
                    ForEach(Array(pin.enumerated()), id: \.offset) { _, digit in
                        Text(String(digit))
                            .font(AppFont.display(size: 32))
                            .foregroundStyle(AppColors.gold)
                            .frame(width: 64, height: 64)
                            .background(AppColors.glassWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppColors.glassBorderGold, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityIdentifier("pin-display")
                Text("Waiting for a device…")
                    .foregroundStyle(AppColors.ivory)
                    .opacity(0.5)
                    .accessibilityIdentifier("hosting-status")
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}

struct DiscoverView: View {
    let devices: [DeviceInfo]
    let status: String
    let onSelect: (DeviceInfo) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 12) {
                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(AppColors.ivory)
                        .accessibilityIdentifier("scan-status")
                }
                if devices.isEmpty {
                    ForEach(0..<3, id: \.self) { _ in
                        GlassCard { Spacer().frame(height: 56) }
                            .opacity(0.5)
                    }
                }
                List(devices, id: \.address) { device in
                    Button(action: { onSelect(device) }) {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(AppColors.gold)
                            VStack(alignment: .leading) {
                                Text(device.name ?? device.address)
                                Text(device.address).font(.caption).foregroundStyle(Color(red: 0xF3/255.0, green: 0xE7/255.0, blue: 0xC3/255.0, opacity: 0.7))
                            }
                        }
                    }
                    .accessibilityIdentifier("device-row")
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
    }
}

struct EnterPinView: View {
    let deviceName: String
    let status: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var pin = ""
    @State private var shake = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            FeltBackground()
            VStack(spacing: 16) {
                Text("Enter the code shown on the host phone")
                    .font(.body)
                    .foregroundStyle(AppColors.ivory)
                Text(deviceName)
                    .font(.headline)
                    .foregroundStyle(AppColors.gold)
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        let digit: String = {
                            let chars = Array(pin)
                            return i < chars.count ? String(chars[i]) : ""
                        }()
                        Text(digit)
                            .font(AppFont.display(size: 28))
                            .foregroundStyle(AppColors.ivory)
                            .frame(width: 56, height: 56)
                            .background(AppColors.glassWhite)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(!digit.isEmpty ? AppColors.gold : AppColors.glassBorderGold, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .accessibilityIdentifier("pin-input")
                .offset(x: shake ? 8 : 0)
                .background(
                    TextField("", text: $pin)
                        .accessibilityIdentifier("pin-field")
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .opacity(0.01)
                        .onChange(of: pin) { _, new in
                            let digits = new.filter(\.isWholeNumber).prefix(4)
                            pin = String(digits)
                            if pin.count == 4 { onConfirm(pin) }
                        }
                )
                .onTapGesture { focused = true }
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(AppColors.error)
                        .accessibilityIdentifier("pin-status")
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(GoldSecondaryButtonStyle())
            }
            .padding(24)
        }
        .onAppear { focused = true }
        .onChange(of: status) { _, new in
            if !new.isEmpty {
                pin = ""
                withAnimation(.linear(duration: 0.05).repeatCount(5, autoreverses: true)) {
                    shake.toggle()
                }
            }
        }
    }
}
