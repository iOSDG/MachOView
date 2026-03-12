/*
 *  DataSources.h
 *  MachOView
 *
 *  Created by psaghelyi on 15/06/2010.
 *
 */

// 外部定义的扫描器错误消息常量
extern NSString * const MVScannerErrorMessage;

// 左侧树形大纲视图的数据源类
@interface MVDataSourceTree : NSObject;
@end


// 右侧详情表格视图的数据源类
@interface MVDataSourceDetails : NSObject;
@end
