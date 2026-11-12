#import <UIKit/UIKit.h>

#include "drivers/apple_embedded/app_delegate_service.h"
#include "drivers/apple_embedded/godot_app_delegate.h"
#include "drivers/apple_embedded/view_controller.h"

// iOS 27 要求应用声明 scene lifecycle。复用 Godot 已创建的窗口和主视图，避免重复创建渲染窗口。
@interface HamsterSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, weak) UIWindowScene *windowScene;
@end

@implementation HamsterSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
	if (![scene isKindOfClass:[UIWindowScene class]]) {
		return;
	}
	UIWindowScene *windowScene = (UIWindowScene *)scene;
	self.windowScene = windowScene;
	self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
	[self.window makeKeyAndVisible];
	[self attachGodotWindow];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
	[self attachGodotWindow];
}

- (void)attachGodotWindow {
	// Godot 创建主视图控制器发生在 UIApplicationDelegate 启动回调中，scene 回调可能更早到达。
	 dispatch_async(dispatch_get_main_queue(), ^{
		GDTAppDelegateService *service = nil;
		for (id candidate in GDTApplicationDelegate.services) {
			if ([candidate isKindOfClass:[GDTAppDelegateService class]]) {
				service = candidate;
				break;
			}
		}
		if (service != nil && GDTAppDelegateService.viewController == nil) {
			// 带 scene manifest 时，部分 iOS 版本不会先转发 Godot 的 AppDelegate 启动回调。
			// 手动补发一次，确保 Godot 引擎和主视图完成初始化。
			[service application:UIApplication.sharedApplication didFinishLaunchingWithOptions:nil];
		}
		GDTViewController *viewController = GDTAppDelegateService.viewController;
		if (viewController != nil) {
			// Godot 的旧 AppDelegate 窗口没有绑定到当前 UIWindowScene。
			// 重新创建 scene 窗口承载同一个 GDTViewController，确保渲染视图收到窗口生命周期回调。
			if (self.window == nil || self.window.windowScene != self.windowScene) {
				self.window = [[UIWindow alloc] initWithWindowScene:self.windowScene];
			}
			self.window.rootViewController = viewController;
			[self.window makeKeyAndVisible];
			 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self attachGodotWindow];
			});
		}
	});
}

@end
