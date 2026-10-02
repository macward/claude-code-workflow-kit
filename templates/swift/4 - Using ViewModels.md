## ViewModel Usage in SwiftUI

### Decision Flow

First match wins:

1. The view only reads or calls a store or service → read it from `@Environment`, no ViewModel
2. It has logic worth unit-testing, or state derived from several sources → `@Observable` ViewModel
3. Otherwise (toggles, form fields, local UI state) → `@State`

### Examples

```swift
// ✅ No ViewModel - only reads a store
struct SessionList: View {
    @Environment(SessionStore.self) private var sessions
    // ...
}

// ✅ ViewModel - logic worth testing
@Observable
final class CheckoutViewModel {
    private let payments: PaymentsService
    func processPayment() async { ... }
}

// ✅ @State - local UI state
struct ExpandableCard: View {
    @State private var isExpanded = false
    // ...
}
```
