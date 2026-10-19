// scripts/screenshots.sh 가 쓰는 보조 도구. 앱(-automation 으로 실행 중)에 분산 알림을 보내 화면을 바꾸고 자기 창을 PNG 로 저장하게 한다.
// 사용: screenshot-post <화면 이름> [저장 경로.png] [WxH]
import Foundation
let a = CommandLine.arguments
guard a.count >= 2 else { print("사용: screenshot-post <화면 이름> [저장 경로.png] [WxH]"); exit(2) }
var info: [String: Any] = ["section": a[1]]
if a.count > 2 { info["capture"] = a[2]; try? FileManager.default.removeItem(atPath: a[2]) }
if a.count > 3 { info["size"] = a[3] }
DistributedNotificationCenter.default().postNotificationName(Notification.Name("com.leobog.control.automation"), object: nil, userInfo: info, deliverImmediately: true)
guard a.count > 2 else { exit(0) }
for _ in 0..<60 {
    if FileManager.default.fileExists(atPath: a[2]) { print("저장: \(a[2])"); exit(0) }
    Thread.sleep(forTimeInterval: 0.2)
}
print("시간 초과: \(a[2]) — 앱이 -automation 으로 실행 중인지 확인하세요"); exit(1)
