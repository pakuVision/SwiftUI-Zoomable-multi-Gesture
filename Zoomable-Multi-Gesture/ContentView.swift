import SwiftUI

struct ContentView: View {
    @Namespace private var imageNamespace
    @State private var showDetail = false
    @State private var animating = false

    var body: some View {
        ZStack {
            if !showDetail {
                VStack {
                    Spacer()
                    Image("Pic 3")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 150)
                        .matchedGeometryEffect(id: "mainImage", in: imageNamespace)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.83)) {
                                showDetail = true
                            }
                        }
                    Spacer()
                }
            } else {
                ImageDetailViewUIKit(namespace: imageNamespace) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.83)) {
                        showDetail = false
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

struct ImageDetailViewUIKit: View {
    var namespace: Namespace.ID
    var onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var parentSize: CGSize = .zero
    @State private var imageSize: CGSize = .zero
    @State private var opacity: CGFloat = 1
    @State private var isPinching = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Color.black.ignoresSafeArea()
                    .opacity(opacity)

                Image("Pic 3")
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: "mainImage", in: namespace)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .background(
                        GeometryReader { imageGeo in
                            Color.clear
                                .onAppear {
                                    imageSize = imageGeo.size
                                }
                        }
                    )
                    .onAppear { parentSize = size }
                    .onChange(of: scale) {
                        // onChange에서는 dismiss 처리 제거
                    }

                UIKitManipulationView(
                    offset: $offset,
                    scale: $scale,
                    isPinching: $isPinching,
                    parentSize: parentSize,
                    imageSize: imageSize,
                    onDismiss: onDismiss
                )
                .frame(width: size.width, height: size.height)
                .background(Color.clear)
                .allowsHitTesting(true)
            }
            .onChange(of: offset) {
                guard !isPinching else { return }
                let opacity = 1 - abs(offset.height / 250)
                self.opacity = max(0, opacity)
            }
            .onChange(of: scale) {
                guard scale < 1 else {
                    self.opacity = 1
                    return
                }
                self.opacity = max(0, scale)
            }
        }
        .transition(.identity)
        .statusBarHidden(true)
    }
}

struct UIKitManipulationView: UIViewRepresentable {
    @Binding var offset: CGSize
    @Binding var scale: CGFloat
    @Binding var isPinching: Bool

    var parentSize: CGSize
    var imageSize: CGSize
    var onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parentSize = parentSize
        context.coordinator.imageSize = imageSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(offset: $offset, scale: $scale, isPinching: $isPinching, parentSize: parentSize, imageSize: imageSize, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var offset: Binding<CGSize>
        var scale: Binding<CGFloat>
        var isPinching: Binding<Bool>
        var parentSize: CGSize
        var imageSize: CGSize
        var onDismiss: () -> Void
        private var lastOffset: CGSize = .zero
        private var lastScale: CGFloat = 1.0

        init(offset: Binding<CGSize>, scale: Binding<CGFloat>, isPinching: Binding<Bool>, parentSize: CGSize, imageSize: CGSize, onDismiss: @escaping () -> Void) {
            self.offset = offset
            self.scale = scale
            self.isPinching = isPinching
            self.parentSize = parentSize
            self.imageSize = imageSize
            self.onDismiss = onDismiss
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            let translation = sender.translation(in: sender.view)
            switch sender.state {
            case .began, .changed:
                offset.wrappedValue = CGSize(width: lastOffset.width + translation.x, height: lastOffset.height + translation.y)
            case .ended, .cancelled:
                lastOffset = offset.wrappedValue
                if lastOffset.height > 130 {
                    onDismiss()
                } else {
                    // 제스처가 끝났을 때 여백 조정
                    adjustOffsetIfNeeded()
                }
            default: break
            }
        }

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            switch sender.state {
            case .began, .changed:
                isPinching.wrappedValue = true
                let newScale = max(0.5, min(lastScale * sender.scale, 3.0))
                scale.wrappedValue = newScale
            case .ended, .cancelled:
                isPinching.wrappedValue = false

                if scale.wrappedValue <= 0.7 {
                    // 0.7 이하에서 제스처가 끝났을 때 dismiss
                    DispatchQueue.main.async {
                        withAnimation(.spring()) {
                            self.onDismiss()
                        }
                    }
                } else if scale.wrappedValue < 1.0 {
                    // 0.7 초과 1 미만일 때 원상복귀
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        scale.wrappedValue = 1.0
                        offset.wrappedValue = .zero
                        lastScale = 1.0
                        lastOffset = .zero
                    }
                } else {
                    lastScale = scale.wrappedValue
                    // 핀치 제스처가 끝났을 때 여백 조정
                    adjustOffsetIfNeeded()
                }
            default: break
            }
        }
        
        private func adjustOffsetIfNeeded() {
            // 스케일이 1 이상일 때만 조정
            guard scale.wrappedValue >= 1.0 else { return }
            
            // 이미지의 실제 크기 계산
            let scaledImageWidth = imageSize.width * scale.wrappedValue
            let scaledImageHeight = imageSize.height * scale.wrappedValue
            
            // 최대/최소 오프셋 계산
            let maxOffsetX = max(0, (scaledImageWidth - parentSize.width) / 2)
            let maxOffsetY = max(0, (scaledImageHeight - parentSize.height) / 2)
            
            var newOffset = offset.wrappedValue
            
            // X축 조정
            if scaledImageWidth > parentSize.width {
                // 이미지가 화면보다 클 때
                if newOffset.width > maxOffsetX {
                    newOffset.width = maxOffsetX
                } else if newOffset.width < -maxOffsetX {
                    newOffset.width = -maxOffsetX
                }
            } else {
                // 이미지가 화면보다 작을 때는 중앙 정렬
                newOffset.width = 0
            }
            
            // Y축 조정
            if scaledImageHeight > parentSize.height {
                // 이미지가 화면보다 클 때
                if newOffset.height > maxOffsetY {
                    newOffset.height = maxOffsetY
                } else if newOffset.height < -maxOffsetY {
                    newOffset.height = -maxOffsetY
                }
            } else {
                // 이미지가 화면보다 작을 때는 중앙 정렬
                newOffset.height = 0
            }
            
            // 애니메이션으로 오프셋 조정
            if newOffset != offset.wrappedValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset.wrappedValue = newOffset
                    lastOffset = newOffset
                }
            }
        }
    }
}
