import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Input,
  Label,
  Switch,
} from "@mks2508/mks-ui/react";
import { FileVideo, Folder, Globe, Play, Search, Square } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";
import type { ILocalFileSource, IStreamSource } from "@/types";

/**
 * Props for the SourcePanel component
 *
 * @property onRun - Callback when user clicks Run with selected source and options
 * @property onStop - Callback when user clicks Stop
 * @property isRunning - Whether a CLI session is currently running
 */
interface ISourcePanelProps {
  onRun: (input: string, opts: { seek: number; duration: number; verbose: boolean }) => void;
  onStop: () => void;
  isRunning: boolean;
}

/**
 * Source selection panel with local files, IPTV URLs, and CLI options
 *
 * Left sidebar component that displays local test files and IPTV sources
 * fetched from the backend, allows CLI option configuration, and triggers
 * CLI execution via Run/Stop buttons.
 *
 * @example
 * ```tsx
 * <SourcePanel onRun={handleRun} onStop={handleStop} isRunning={false} />
 * ```
 */
export function SourcePanel({ onRun, onStop, isRunning }: ISourcePanelProps) {
  const [localFiles, setLocalFiles] = useState<ILocalFileSource[]>([]);
  const [iptvSources, setIptvSources] = useState<IStreamSource[]>([]);
  const [selectedInput, setSelectedInput] = useState<string>("");
  const [seek, setSeek] = useState(0);
  const [duration, setDuration] = useState(10);
  const [verbose, setVerbose] = useState(true);
  const [searchQuery, setSearchQuery] = useState("");

  useEffect(() => {
    const fetchSources = async () => {
      try {
        const [localRes, iptvRes] = await Promise.all([
          api.sources.local.get(),
          api.sources.index.get(),
        ]);

        if (localRes.data) {
          setLocalFiles(
            (localRes.data as { files: ILocalFileSource[] }).files ?? []
          );
        }
        if (iptvRes.data) {
          setIptvSources(
            (iptvRes.data as { sources: IStreamSource[] }).sources ?? []
          );
        }
      } catch {
        // Sources endpoint may not be ready
      }
    };

    fetchSources();
  }, []);

  const filteredIPTV = useMemo(() => {
    if (!searchQuery.trim()) return iptvSources.slice(0, 30);
    const q = searchQuery.toLowerCase();
    return iptvSources
      .filter((s) => s.name.toLowerCase().includes(q))
      .slice(0, 30);
  }, [iptvSources, searchQuery]);

  const handleRun = useCallback(() => {
    if (!selectedInput) return;
    onRun(selectedInput, { seek, duration, verbose });
  }, [selectedInput, seek, duration, verbose, onRun]);

  const formatSize = (bytes: number): string => {
    if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)}G`;
    if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)}M`;
    return `${(bytes / 1e3).toFixed(0)}K`;
  };

  return (
    <div className="flex flex-col gap-2 h-full overflow-y-auto p-2 scrollbar-thin">
      {/* Local Files */}
      <Card className="glass border-border/30 rounded-lg">
        <CardHeader className="pb-1.5 pt-2.5 px-3">
          <CardTitle className="font-mono-emphasis text-[11px] uppercase tracking-widest flex items-center gap-2 text-muted-foreground">
            <Folder className="size-3 text-primary" />
            Local Files
            <Badge variant="outline" className="ml-auto font-mono text-[9px] h-4 px-1.5">
              {localFiles.length}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="px-2 pb-2 space-y-0.5">
          {localFiles.map((file) => (
            <button
              key={file.path}
              type="button"
              onClick={() => setSelectedInput(file.path)}
              className={`w-full text-left px-2 py-1.5 rounded-md text-[11px] font-mono transition-all cursor-pointer group ${
                selectedInput === file.path
                  ? "bg-primary/15 text-primary border border-primary/25"
                  : "hover:bg-accent/40 text-foreground/70 border border-transparent"
              }`}
            >
              <div className="flex items-center gap-1.5 min-w-0">
                <FileVideo className="size-3 shrink-0 text-muted-foreground group-hover:text-primary/70 transition-colors" />
                <span className="truncate leading-tight">{file.name}</span>
              </div>
              <div className="flex items-center gap-1.5 mt-0.5 pl-[18px]">
                <Badge
                  variant="outline"
                  className={`text-[8px] px-1 py-0 h-3.5 uppercase leading-none ${
                    file.extension === "mkv"
                      ? "border-primary/40 text-primary"
                      : "border-border/50 text-muted-foreground"
                  }`}
                >
                  {file.extension}
                </Badge>
                <span className="text-[9px] text-muted-foreground/60">
                  {formatSize(file.size)}
                </span>
              </div>
            </button>
          ))}
        </CardContent>
      </Card>

      {/* IPTV URLs */}
      <Card className="glass border-border/30 rounded-lg flex-1 min-h-0 flex flex-col">
        <CardHeader className="pb-1.5 pt-2.5 px-3 shrink-0">
          <CardTitle className="font-mono-emphasis text-[11px] uppercase tracking-widest flex items-center gap-2 text-muted-foreground">
            <Globe className="size-3 text-primary" />
            IPTV Streams
            <Badge variant="outline" className="ml-auto font-mono text-[9px] h-4 px-1.5">
              {iptvSources.length}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="px-2 pb-2 space-y-1.5 flex-1 min-h-0 flex flex-col">
          <div className="relative shrink-0">
            <Search className="absolute left-2 top-1/2 -translate-y-1/2 size-3 text-muted-foreground/50" />
            <Input
              placeholder="Filter streams..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="h-6 text-[11px] font-mono pl-7 bg-background/30 border-border/30"
            />
          </div>
          <div className="flex-1 overflow-y-auto space-y-0.5 scrollbar-thin min-h-0">
            {filteredIPTV.map((source) => (
              <button
                key={source.id}
                type="button"
                onClick={() => setSelectedInput(source.url)}
                className={`w-full text-left px-2 py-1.5 rounded-md text-[11px] font-mono transition-all cursor-pointer ${
                  selectedInput === source.url
                    ? "bg-primary/15 text-primary border border-primary/25"
                    : "hover:bg-accent/40 text-foreground/70 border border-transparent"
                }`}
              >
                <span className="truncate block leading-tight">{source.name}</span>
                <div className="flex items-center gap-1 mt-0.5">
                  <Badge
                    variant="outline"
                    className={`text-[8px] px-1 py-0 h-3.5 uppercase leading-none ${
                      source.containerExtension === "mkv"
                        ? "border-primary/40 text-primary"
                        : "border-border/50 text-muted-foreground"
                    }`}
                  >
                    {source.containerExtension}
                  </Badge>
                  <span className="text-[9px] text-muted-foreground/50 truncate">
                    {source.category}
                  </span>
                </div>
              </button>
            ))}
            {filteredIPTV.length === 0 && (
              <div className="text-center py-4 text-[10px] text-muted-foreground/40 font-mono">
                No streams found
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* CLI Options + Run */}
      <Card className="glass border-border/30 rounded-lg shrink-0">
        <CardHeader className="pb-1.5 pt-2.5 px-3">
          <CardTitle className="font-mono-emphasis text-[11px] uppercase tracking-widest text-muted-foreground">
            CLI Options
          </CardTitle>
        </CardHeader>
        <CardContent className="px-3 pb-3 space-y-2.5">
          <div className="grid grid-cols-2 gap-2">
            <div className="space-y-1">
              <Label className="text-[10px] font-mono text-muted-foreground/70 uppercase tracking-wider">
                Seek (s)
              </Label>
              <Input
                type="number"
                min={0}
                value={seek}
                onChange={(e) => setSeek(Number(e.target.value))}
                className="h-7 text-[11px] font-mono bg-background/30 border-border/30"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-[10px] font-mono text-muted-foreground/70 uppercase tracking-wider">
                Duration (s)
              </Label>
              <Input
                type="number"
                min={1}
                value={duration}
                onChange={(e) => setDuration(Number(e.target.value))}
                className="h-7 text-[11px] font-mono bg-background/30 border-border/30"
              />
            </div>
          </div>

          <div className="flex items-center justify-between py-0.5">
            <Label className="text-[10px] font-mono text-muted-foreground/70 uppercase tracking-wider">
              Verbose
            </Label>
            <Switch checked={verbose} onCheckedChange={setVerbose} />
          </div>

          <Button
            onClick={isRunning ? onStop : handleRun}
            disabled={!selectedInput && !isRunning}
            variant={isRunning ? "destructive" : "default"}
            className="w-full font-mono-emphasis text-[11px] h-8 tracking-wider uppercase"
            size="sm"
          >
            {isRunning ? (
              <>
                <Square className="size-3" />
                Stop Session
              </>
            ) : (
              <>
                <Play className="size-3" />
                Run Transmux
              </>
            )}
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
