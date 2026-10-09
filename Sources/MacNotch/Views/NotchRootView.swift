import SwiftUI

/// Root view hosted inside the notch panel. It draws the black "island" whose
/// size changes with the view model's visual state.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var music: MusicManager
    @ObservedObject var briefs: BriefsModel

    var body: some View {
        content
            .frame(
                width: viewModel.currentSize.width,
                height: viewModel.currentSize.height
            )
            .background(
                NotchShape(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                )
                .fill(Color.black)
            )
            .clipShape(
                NotchShape(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                )
            )
            .shadow(
                color: viewModel.visualState == .hidden ? .clear : .black.opacity(0.45),
                radius: 18, y: 8
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.visualState {
        case .hidden:
            HiddenNotchView()
                .opacity(0)
        case .peek:
            PeekView(music: music, notchHeight: viewModel.notchSize.height)
                .transition(.opacity)
        case .expanded:
            ExpandedView(viewModel: viewModel, music: music, briefs: briefs)
                .transition(.opacity)
        }
    }
}
