import SwiftUI

struct SearchBar: View {
    @Binding var searchText: String
    let onClearAll: () -> Void
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            // Search field
            TextField("Search clips...", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            // Clear all button
            Button(action: onClearAll) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .disabled(!isEnabled)
            .help("Clear all clips")
        }
        .padding(.horizontal)
    }
}

struct SearchBar_Previews: PreviewProvider {
    static var previews: some View {
        SearchBar(
            searchText: .constant(""),
            onClearAll: {},
            isEnabled: true
        )
        .frame(width: 300)
        .padding()
    }
}
