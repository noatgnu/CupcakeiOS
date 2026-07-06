import SwiftUI

struct SDRFAgeInputView: View {
    @Binding var years: String
    @Binding var months: String
    @Binding var days: String

    var body: some View {
        TextField("Years", text: $years)
            .accessibilityIdentifier("sdrfAgeYearsField")
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        TextField("Months", text: $months)
            .accessibilityIdentifier("sdrfAgeMonthsField")
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
        TextField("Days", text: $days)
            .accessibilityIdentifier("sdrfAgeDaysField")
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
    }
}
