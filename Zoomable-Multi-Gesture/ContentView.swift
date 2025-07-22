import SwiftUI

struct ContentView: View {
    @Namespace private var imageNamespace
    @State private var showDetail = false
    @State private var selectedIndex = 0

    let images = ["p1", "p2", "p3", "p4"]

    var body: some View {
        ZStack {
            if !showDetail {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(images.indices, id: \.self) { idx in
                            Image(images[idx])
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 120)
                                .cornerRadius(16)
                                .shadow(radius: 3)
                                .matchedGeometryEffect(id: "mainImage\(idx)", in: imageNamespace)
                                .onTapGesture {
                                    selectedIndex = idx
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.83)) {
                                        showDetail = true
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 100)
                }
            } else {
                ImageDetailPagerView(
                    images: images,
                    initialIndex: selectedIndex,
                    namespace: imageNamespace
                ) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.83)) {
                        showDetail = false
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

// MARK: - 풀스크린 페이징 디테일 뷰

struct ImageDetailPagerView: View {
    let images: [String]
    let initialIndex: Int
    let namespace: Namespace.ID
    var onDismiss: () -> Void

    @State private var selection: Int

    init(images: [String], initialIndex: Int, namespace: Namespace.ID, onDismiss: @escaping () -> Void) {
        self.images = images
        self.initialIndex = initialIndex
        self.namespace = namespace
        self.onDismiss = onDismiss
        _selection = State(initialValue: initialIndex)
    }

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(images.indices, id: \.self) { idx in
                    ImageDetailViewUIKit(
                        imageName: images[idx],
                        tag: idx,
                        namespace: namespace,
                        onDismiss: onDismiss
                    )
                    .tag(idx)
                }
            }
            .disabled(true)
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
        }
        .transition(.identity)
        .statusBarHidden(true)
    }
}

// MARK: - 한 장의 풀스크린 확대뷰(핀치/드래그/복귀/엣지보정 포함)

struct ImageDetailViewUIKit: View {
    let imageName: String
    let tag: Int
    let namespace: Namespace.ID
    var onDismiss: () -> Void

    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var parentSize: CGSize = .zero
    @State private var imageSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                Color.black.ignoresSafeArea()

                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: "mainImage\(tag)", in: namespace)
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

                UIKitManipulationView(
                    offset: $offset,
                    scale: $scale,
                    parentSize: parentSize,
                    imageSize: imageSize,
                    onDismiss: onDismiss
                )
                .frame(width: size.width, height: size.height)
                .background(Color.clear)
                .allowsHitTesting(true)
            }
        }
        .transition(.identity)
    }
}

// MARK: - UIKitManipulationView (수정 필요 없음: 기존 코드 활용)

struct UIKitManipulationView: UIViewRepresentable {
    @Binding var offset: CGSize
    @Binding var scale: CGFloat

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
        Coordinator(offset: $offset, scale: $scale, parentSize: parentSize, imageSize: imageSize, onDismiss: onDismiss)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var offset: Binding<CGSize>
        var scale: Binding<CGFloat>
        var parentSize: CGSize
        var imageSize: CGSize
        var onDismiss: () -> Void
        private var lastOffset: CGSize = .zero
        private var lastScale: CGFloat = 1.0

        init(offset: Binding<CGSize>, scale: Binding<CGFloat>, parentSize: CGSize, imageSize: CGSize, onDismiss: @escaping () -> Void) {
            self.offset = offset
            self.scale = scale
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
                if abs(lastOffset.height) > 130 {
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
                let newScale = max(0.7, min(lastScale * sender.scale, 3.0))
                scale.wrappedValue = newScale
            case .ended, .cancelled:
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
                if newOffset.width > maxOffsetX {
                    newOffset.width = maxOffsetX
                } else if newOffset.width < -maxOffsetX {
                    newOffset.width = -maxOffsetX
                }
            } else {
                newOffset.width = 0
            }
            
            // Y축 조정
            if scaledImageHeight > parentSize.height {
                if newOffset.height > maxOffsetY {
                    newOffset.height = maxOffsetY
                } else if newOffset.height < -maxOffsetY {
                    newOffset.height = -maxOffsetY
                }
            } else {
                newOffset.height = 0
            }
            
            if newOffset != offset.wrappedValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset.wrappedValue = newOffset
                    lastOffset = newOffset
                }
            }
        }
    }
}
