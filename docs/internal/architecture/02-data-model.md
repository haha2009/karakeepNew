# 数据模型

## 核心表

### users
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text (UUID) | 主键 |
| email | text | 邮箱 (唯一) |
| name | text | 显示名 |
| role | enum | user / admin |

### bookmarks (核心实体)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text (UUID) | 主键 |
| userId | text | FK → users |
| url | text | 链接 |
| title | text | 标题 |
| description | text | 描述 |
| note | text | 用户备注 |
| summary | text | AI 生成摘要 |
| image | text | 封面图 URL |
| favicon | text | 网站图标 |
| content | text | 爬取正文 |
| htmlContent | text | 原始 HTML |
| textContent | text | 纯文本 |
| readabilityContent | text | Readability 提取 |
| created_at | datetime | 创建时间 |
| updated_at | datetime | 更新时间 |
| status | enum | active / archived / deleted |
| favourite | boolean | 收藏 |

### tags
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text (UUID) | 主键 |
| userId | text | FK → users |
| name | text | 标签名 (唯一 per user) |
| color | text | 颜色 |
| aiAttached | boolean | AI 自动打标 |

### bookmark_tags (多对多)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| bookmarkId | text | FK → bookmarks |
| tagId | text | FK → tags |
| attachedBy | enum | user / ai |

### lists (收藏夹)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| userId | text | FK → users |
| name | text | 名称 |
| description | text | 描述 |
| icon | text | 图标 |

### list_bookmarks (多对多)
list 与 bookmark 的多对多关系，含排序字段。

### assets (爬取资源)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| bookmarkId | text | FK → bookmarks |
| assetType | enum | html / pdf / screenshot / video / unknown |
| mimeType | text | MIME 类型 |
| originalUrl | text | 原始 URL |
| content | blob | 二进制内容 |
| contentHash | text | 内容哈希 (去重) |

### highlights (高亮批注)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| bookmarkId | text | FK → bookmarks |
| userId | text | FK → users |
| text | text | 选中文本 |
| note | text | 批注 |
| color | text | 高亮颜色 |
| position | json | 位置信息 |

### feeds (RSS 订阅)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| userId | text | FK → users |
| url | text | RSS URL |
| title | text | 标题 |
| icon | text | 图标 |
| refreshInterval | int | 刷新间隔 (分钟) |
| lastRefreshedAt | datetime | 上次刷新 |

### rules (自动规则)
| 字段 | 类型 | 说明 |
|------|------|------|
| id | text | 主键 |
| userId | text | FK → users |
| name | text | 规则名 |
| conditions | json | 条件组 (AND/OR) |
| actions | json | 动作 (打标/归档/收藏) |
| enabled | boolean | 启用 |

## 关系图

```
users ──< bookmarks ──< assets
  │          │
  │          ├──< highlights
  │          │
  │          ├──< bookmark_tags >── tags
  │          │
  │          └──< list_bookmarks >── lists
  │
  ├──< feeds
  ├──< rules
  └──< webhooks
```

## 索引策略

- bookmarks: (userId, status) — 用户视图筛选
- bookmarks: (userId, created_at) — 排序
- tags: (userId, name) — 唯一标签
- assets: (bookmarkId) — 按书签查找资源
- assets: (contentHash) — 去重查询
