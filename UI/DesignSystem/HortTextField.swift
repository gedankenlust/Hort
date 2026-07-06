import SwiftUI

/// Styled text field with visible editable background and focus ring.
struct HortTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var leadingIcon: String? = nil
    var trailingView: AnyView? = nil

    /// Optional externally-controlled focus via a plain `Binding<Bool>`.
    /// Prefer `focusState` when the caller uses `@FocusState`.
    var focus: Binding<Bool>? = nil

    /// Optional externally-controlled focus via a `@FocusState` projection.
    var focusState: FocusState<Bool>.Binding? = nil

    @FocusState private var internalFocus: Bool

    init(placeholder: LocalizedStringKey,
         text: Binding<String>,
         onSubmit: (() -> Void)? = nil,
         leadingIcon: String? = nil,
         trailingView: AnyView? = nil,
         focus: Binding<Bool>? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.leadingIcon = leadingIcon
        self.trailingView = trailingView
        self.focus = focus
    }

    init(placeholder: LocalizedStringKey,
         text: Binding<String>,
         onSubmit: (() -> Void)? = nil,
         leadingIcon: String? = nil,
         trailingView: AnyView? = nil,
         focus: FocusState<Bool>.Binding?) {
        self.placeholder = placeholder
        self._text = text
        self.onSubmit = onSubmit
        self.leadingIcon = leadingIcon
        self.trailingView = trailingView
        self.focusState = focus
    }

    private var activeFocus: FocusState<Bool>.Binding {
        focusState ?? $internalFocus
    }

    var body: some View {
        HStack(spacing: HortSpacing.sm) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: 11))
                    .foregroundColor(HortColors.textTertiary)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(HortTypography.primary())
                .foregroundColor(HortColors.textPrimary)
                .focused(activeFocus)
                .onSubmit { onSubmit?() }

            if let trailingView {
                trailingView
            }
        }
        .padding(.horizontal, HortSpacing.md)
        .padding(.vertical, HortSpacing.sm + 1)
        .background(HortColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous)
                .strokeBorder(isFocused ? HortColors.borderFocus : HortColors.borderStrong,
                              lineWidth: isFocused ? 1.5 : 1)
        )
        .onAppear {
            if let focus {
                internalFocus = focus.wrappedValue
            }
        }
        .onChange(of: internalFocus) { _, newValue in
            focus?.wrappedValue = newValue
        }
        .onChange(of: focus?.wrappedValue ?? false) { _, newValue in
            guard focusState == nil else { return }
            internalFocus = newValue
        }
    }

    private var isFocused: Bool {
        focus?.wrappedValue ?? focusState?.wrappedValue ?? internalFocus
    }
}
