# Content-Aware Renderers

This directory contains the content-aware rendering system for LinkContentPreview. It allows for special rendering of different types of links based on their URL patterns.

## Architecture

The system consists of:

1. **Types** (`types.ts`): Defines the `ContentRenderer` interface
2. **Registry** (`registry.ts`): Manages registration and retrieval of renderers
3. **Individual Renderers**: Each renderer handles a specific type of content

## Creating a New Renderer

To add support for a new website or content type:

1. Create a new file (e.g., `MyWebsiteRenderer.tsx`)
2. Implement the `ContentRenderer` interface using shared utilities:

```typescript
import { ContentRenderer } from "./types";
import { canRenderLinkType, extractFromUrl } from "./renderer-utils";

const URL_PATTERNS = [/mywebsite\.com\/(.+)/];

function canRenderMyWebsite(bookmark: ZBookmark): boolean {
  if (!canRenderLinkType(bookmark)) return false;
  return extractFromUrl(bookmark.content.url, URL_PATTERNS) !== null;
}

function MyWebsiteRendererComponent({ bookmark }: { bookmark: ZBookmark }) {
  const id = bookmark.content.type === "link"
    ? extractFromUrl(bookmark.content.url, URL_PATTERNS)
    : null;

  if (!id) return null;

  return <div>Custom content for MyWebsite</div>;
}

export const myWebsiteRenderer: ContentRenderer = {
  id: "mywebsite",
  name: "My Website",
  icon: MyIcon,
  canRender: canRenderMyWebsite,
  component: MyWebsiteRendererComponent,
  priority: 10, // Higher priority = appears first in dropdown
};
```

3. Register your renderer in `index.ts`:

```typescript
import { myWebsiteRenderer } from "./MyWebsiteRenderer";

contentRendererRegistry.register(myWebsiteRenderer);
```

## Error Handling

Custom renderers are wrapped in an `<ErrorBoundary>` by `LinkContentSection.tsx`. If a renderer throws during rendering, the fallback UI shows:

- Error message with expandable technical details
- **"Switch to Reader View"** button — clicking it switches the view to the cached Reader View

For renderer-specific error handling (e.g., iframe load failures), use React state:

```typescript
function MyRendererComponent({ bookmark }: { bookmark: ZBookmark }) {
  const [loadError, setLoadError] = useState(false);

  if (loadError) {
    return <a href={url} target="_blank" rel="noopener noreferrer">View original</a>;
  }

  return <iframe src={url} onError={() => setLoadError(true)} />;
}
```

## Shared Utilities

- `canRenderLinkType(bookmark)` — checks if bookmark type is a link
- `extractFromUrl(url, patterns)` — extracts first capture group from URL regex patterns

Import from `./renderer-utils`.
