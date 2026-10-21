/// 보여줄 플레이어 고르기. 명세 4.5.2.
/// 플레이어마다 마지막 상태를 기억하고, 상태가 바뀔 때마다 보여줄 플레이어를 정한다.
struct PlayerChooser {
    typealias State = NowPlayingInfo.State

    private(set) var shown: PlayerKind?
    private var states: [PlayerKind: State] = [:]

    func state(of kind: PlayerKind) -> State {
        states[kind] ?? .stopped
    }

    mutating func update(_ kind: PlayerKind, _ state: State) {
        let previous = self.state(of: kind)
        states[kind] = state
        let others = PlayerKind.allCases.filter { $0 != kind }

        if shown == kind {
            if previous == .playing, state == .paused, let other = others.first(where: { self.state(of: $0) == .playing }) {
                shown = other
            } else if state == .stopped, let other = others.first(where: { self.state(of: $0) == .playing })
                        ?? others.first(where: { self.state(of: $0) == .paused }) {
                shown = other
            }
            return
        }

        // 보여주는 플레이어가 없거나 정지 상태면 이 플레이어를 보여준다.
        guard let current = shown, self.state(of: current) != .stopped else {
            if state != .stopped { shown = kind }
            return
        }
        // 다른 플레이어가 재생을 시작했다. 보여주는 쪽이 재생 중이면 무시한다.
        // 재생 중 다음 곡으로 넘어가는 것(재생 → 재생)은 시작이 아니다.
        if previous != .playing, state == .playing, self.state(of: current) != .playing {
            shown = kind
        }
    }

    /// 메뉴에서 고른 플레이어. 다음 상태 변화가 있을 때까지 그대로 보여준다.
    mutating func choose(_ kind: PlayerKind) {
        shown = kind
    }
}
