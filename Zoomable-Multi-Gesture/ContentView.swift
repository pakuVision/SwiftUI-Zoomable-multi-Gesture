import SwiftUI
import UIKit
import Combine

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

// MARK: - UIPageViewController를 사용한 페이저 뷰

struct ImageDetailPagerView: View {
    let images: [String]
    let initialIndex: Int
    let namespace: Namespace.ID
    var onDismiss: () -> Void
    
    @StateObject private var pageManager = PageManager()

    var body: some View {
        PageViewController(
            images: images,
            initialIndex: initialIndex,
            namespace: namespace,
            onDismiss: onDismiss,
            pageManager: pageManager
        )
        .ignoresSafeArea()
        .statusBarHidden(true)
    }
}

// MARK: - PageManager: 페이징 상태 관리

class PageManager: ObservableObject {
    @Published var isPagingEnabled = true
    
    func updatePagingEnabled(_ enabled: Bool) {
        isPagingEnabled = enabled
    }
}


// MARK: - UIPageViewController Wrapper

struct PageViewController: UIViewControllerRepresentable {
    let images: [String]
    let initialIndex: Int
    let namespace: Namespace.ID
    var onDismiss: () -> Void
    @ObservedObject var pageManager: PageManager
    
    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator
        
        // 초기 페이지 설정
        if let initialVC = context.coordinator.createViewController(at: initialIndex) {
            pageVC.setViewControllers([initialVC], direction: .forward, animated: false)
        }
        
        // 배경색 설정
        pageVC.view.backgroundColor = .black
        
        return pageVC
    }
    
    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        // 페이징 활성화/비활성화
        if let scrollView = pageVC.view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.isScrollEnabled = pageManager.isPagingEnabled
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        let parent: PageViewController
        
        init(_ parent: PageViewController) {
            self.parent = parent
        }
        
        func createViewController(at index: Int) -> UIViewController? {
            guard index >= 0 && index < parent.images.count else { return nil }
            
            let hostingController = UIHostingController(
                rootView: ImageDetailView(
                    imageName: parent.images[index],
                    tag: index,
                    namespace: parent.namespace,
                    onDismiss: parent.onDismiss,
                    pageManager: parent.pageManager
                )
            )
            hostingController.view.backgroundColor = .black
            hostingController.view.tag = index  // 인덱스를 태그로 저장
            return hostingController
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            let currentIndex = viewController.view.tag
            return createViewController(at: currentIndex - 1)
        }
        
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            let currentIndex = viewController.view.tag
            return createViewController(at: currentIndex + 1)
        }
    }
}

// MARK: - 개별 이미지 상세 뷰

struct ImageDetailView: View {
    let imageName: String
    let tag: Int
    let namespace: Namespace.ID
    var onDismiss: () -> Void
    @ObservedObject var pageManager: PageManager

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
                    .onChange(of: scale) { newScale in
                        // 스케일에 따라 페이징 활성화/비활성화
                        pageManager.updatePagingEnabled(newScale <= 1.0)
                    }

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

// MARK: - UIKitManipulationView (기존과 동일)

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
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        
        doubleTap.numberOfTapsRequired = 2
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator

        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(doubleTap)
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
            // 스케일이 1일 때는 pan 제스처를 무시
            guard scale.wrappedValue > 1.0 else { return }
            
            let translation = sender.translation(in: sender.view)
            switch sender.state {
            case .began, .changed:
                offset.wrappedValue = CGSize(width: lastOffset.width + translation.x, height: lastOffset.height + translation.y)
            case .ended, .cancelled:
                lastOffset = offset.wrappedValue
                // 제스처가 끝났을 때 여백 조정
                adjustOffsetIfNeeded()
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
        
        @objc func handleDoubleTap(_ sender: UITapGestureRecognizer) {
            // 더블탭으로 스케일 1로 원상복귀
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                scale.wrappedValue = 1.0
                offset.wrappedValue = .zero
                lastScale = 1.0
                lastOffset = .zero
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
