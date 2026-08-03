# Turn an AI-generated pixel-art contact sheet into the 16-px strip the mod
# wants: strip the drawn checkerboard, strip the frame lines, split the grid,
# downsample each cell to 16x16 and lay them out in one horizontal row.
param(
  [Parameter(Mandatory=$true)][string]$In,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Cols = 0,
  [int]$Rows = 0,
  [int]$BgLo = 198,
  [int]$BgHi = 255
)

Add-Type -AssemblyName System.Drawing

if (-not ("SheetStrip" -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class SheetStrip {
  static int W, H, stride;
  static byte[] px;
  static bool hasAlpha;

  static int R(int x,int y){ return px[y*stride+x*4+2]; }
  static int G(int x,int y){ return px[y*stride+x*4+1]; }
  static int B(int x,int y){ return px[y*stride+x*4+0]; }
  static int A(int x,int y){ return px[y*stride+x*4+3]; }

  // What counts as BACKGROUND, as a luminance window -- because the three
  // sheets came back on three different backgrounds and none of them was
  // transparency: a drawn checkerboard (white and ~90% grey), a black field
  // with a soft white glow around each drawing, and a flat mid grey.
  //
  // A window plus the flood fill covers all three. The footprints are the
  // case that shows why it has to be a fill rather than a threshold: their
  // interior is DARKER than the background they sit on, and the only thing
  // separating the two is the light outline the fill cannot cross.
  static int bgLo = 198, bgHi = 255;

  static bool IsBg(int x,int y){
    if (hasAlpha) return A(x,y) < 128;
    int r=R(x,y), g=G(x,y), b=B(x,y);
    int mx=Math.Max(r,Math.Max(g,b)), mn=Math.Min(r,Math.Min(g,b));
    if (mx-mn > 24) return false;              // coloured: not this paper
    int lum = (int)(0.299*r + 0.587*g + 0.114*b);
    return lum >= bgLo && lum <= bgHi;
  }

  static bool IsInk(int x,int y){
    return A(x,y) > 128 && R(x,y) < 130 && G(x,y) < 130 && B(x,y) < 130;
  }

  // Clear any run longer than `max`: a rule is thin, a band of art is not.
  static void Thin(bool[] f, int max){
    int s = -1;
    for (int i=0;i<=f.Length;i++){
      bool on = i < f.Length && f[i];
      if (on) { if (s<0) s=i; }
      else if (s>=0) {
        if (i-s > max) for (int j=s;j<i;j++) f[j] = false;
        s = -1;
      }
    }
  }

  static List<int[]> Runs(bool[] f){
    var runs = new List<int[]>(); int s=-1;
    for (int i=0;i<f.Length;i++){
      if (f[i]) { if (s<0) s=i; }
      else if (s>=0) { runs.Add(new int[]{s,i-1}); s=-1; }
    }
    if (s>=0) runs.Add(new int[]{s,f.Length-1});
    return runs;
  }

  // The gaps between the ink runs, keeping only the `want` WIDEST of them.
  //
  // Keeping all of them was wrong in both directions on real sheets: the
  // outer border leaves a thin margin on each side, and a margin is a gap
  // between ink runs exactly like a cell is -- so a 3-column sheet came back
  // as 5. And a stray dark pixel inside the art splits one cell into two.
  // The caller knows the layout it asked the generator for, so it says.
  static List<int[]> Gaps(List<int[]> runs, int len, int want){
    var g = new List<int[]>(); int prev=0;
    foreach (var r in runs){
      if (r[0]-prev > 4) g.Add(new int[]{prev, r[0]-1});
      prev = r[1]+1;
    }
    if (len-prev > 4) g.Add(new int[]{prev, len-1});
    if (g.Count == 0) g.Add(new int[]{0, len-1});
    if (want > 0 && g.Count > want){
      g.Sort(delegate(int[] a, int[] b){ return (b[1]-b[0]).CompareTo(a[1]-a[0]); });
      g = g.GetRange(0, want);
      g.Sort(delegate(int[] a, int[] b){ return a[0].CompareTo(b[0]); });
    }
    return g;
  }

  public static string Convert(string inPath, string outPath, int wantCols, int wantRows, int lo, int hi){
    bgLo = lo; bgHi = hi;
    var src = (Bitmap)Bitmap.FromFile(inPath);
    W = src.Width; H = src.Height;
    var data = src.LockBits(new Rectangle(0,0,W,H), ImageLockMode.ReadOnly,
                            PixelFormat.Format32bppArgb);
    stride = data.Stride;
    px = new byte[stride*H];
    Marshal.Copy(data.Scan0, px, 0, px.Length);
    src.UnlockBits(data); src.Dispose();

    hasAlpha = false;
    for (int y=0;y<H && !hasAlpha;y++)
      for (int x=0;x<W;x++)
        if (px[y*stride+x*4+3] < 200) { hasAlpha = true; break; }

    // frame lines: rows/columns that are overwhelmingly dark ink
    // A rule crosses the WHOLE sheet and is a few pixels thick. Both halves
    // of that matter: at a 55% coverage threshold a row passing through three
    // dark puddles counted as a rule, and the "inner rect" came back as the
    // middle of the drawing -- so the cells were cut through the art. 75%
    // coverage plus a thickness cap says "rule" and nothing else does.
    var colDark = new bool[W];
    for (int x=0;x<W;x++){ int n=0; for (int y=0;y<H;y++) if (IsInk(x,y)) n++;
                           colDark[x] = n > H*0.75; }
    var rowDark = new bool[H];
    for (int y=0;y<H;y++){ int n=0; for (int x=0;x<W;x++) if (IsInk(x,y)) n++;
                           rowDark[y] = n > W*0.75; }
    Thin(colDark, W/60 + 3);
    Thin(rowDark, H/60 + 3);

    // The OUTER border only, and then an equal division of what is inside it.
    //
    // Reading the interior lines as the grid looked cleverer and was worse:
    // the middle rule of one sheet was a shade too pale to count as ink, so
    // its two rows of art merged into one "cell" and the top margin became
    // the other -- three empty frames and three squashed ones. The caller
    // knows the layout it asked the generator for, so the only thing that has
    // to be found is where the drawing starts.
    int L=0, Rr=W-1, T=0, Bm=H-1;
    for (int x=0;x<W/3;x++) if (colDark[x]) L = x+1;
    for (int x=W-1;x>W*2/3;x--) if (colDark[x]) Rr = x-1;
    for (int y=0;y<H/3;y++) if (rowDark[y]) T = y+1;
    for (int y=H-1;y>H*2/3;y--) if (rowDark[y]) Bm = y-1;
    int iw = Rr-L+1, ih = Bm-T+1;
    int nc = wantCols > 0 ? wantCols : 1, nr = wantRows > 0 ? wantRows : 1;

    var cols = new List<int[]>();
    for (int i=0;i<nc;i++){
      int a = L + (int)((long)i*iw/nc), b = L + (int)((long)(i+1)*iw/nc) - 1;
      int pad = (b-a+1)/40 + 1;          // clear of the rule between cells
      cols.Add(new int[]{a+pad, b-pad});
    }
    var rows = new List<int[]>();
    for (int i=0;i<nr;i++){
      int a = T + (int)((long)i*ih/nr), b = T + (int)((long)(i+1)*ih/nr) - 1;
      int pad = (b-a+1)/40 + 1;
      rows.Add(new int[]{a+pad, b-pad});
    }

    // ------- pass one: where the drawing actually is inside its cell
    //
    // A generator leaves a lot of paper around a drawing, and paper
    // downsampled to a 16x16 frame is frame spent on nothing: the footprints
    // came back two pixels wide because most of their cell was margin. So
    // the art's own bounding box is measured and the crop is taken from
    // that instead of from the cell.
    //
    // ONE box for the whole sheet, not one per cell, and that is the point:
    // per-cell boxes would scale every drawing up to the same size and throw
    // away the size variety the sheet was drawn with. The union keeps the
    // relative sizes and only removes the margin they have in common.
    int ux0=int.MaxValue, uy0=int.MaxValue, ux1=int.MinValue, uy1=int.MinValue;
    foreach (var rc in rows) foreach (var cc in cols) {
      int cx0=cc[0], cy0=rc[0], cw=cc[1]-cc[0]+1, ch=rc[1]-rc[0]+1;
      for (int y=0;y<ch;y++) for (int x=0;x<cw;x++)
        if (!IsBg(cx0+x, cy0+y)) {
          if (x<ux0) ux0=x; if (x>ux1) ux1=x;
          if (y<uy0) uy0=y; if (y>uy1) uy1=y;
        }
    }
    int cw0 = cols[0][1]-cols[0][0]+1, ch0 = rows[0][1]-rows[0][0]+1;
    if (ux1 < ux0) { ux0=0; ux1=cw0-1; uy0=0; uy1=ch0-1; }
    // a little air, so nothing lands hard against the frame's edge
    int mx = (ux1-ux0+1)/14 + 1, my = (uy1-uy0+1)/14 + 1;
    ux0 = Math.Max(0, ux0-mx); uy0 = Math.Max(0, uy0-my);
    ux1 = Math.Min(cw0-1, ux1+mx); uy1 = Math.Min(ch0-1, uy1+my);
    // and square it, so a wide drawing is not stretched tall by the 16x16
    int bw = ux1-ux0+1, bh = uy1-uy0+1;
    if (bw > bh) { int add=(bw-bh)/2; uy0-=add; uy1+=add; }
    else if (bh > bw) { int add=(bh-bw)/2; ux0-=add; ux1+=add; }
    ux0 = Math.Max(0, ux0); uy0 = Math.Max(0, uy0);
    ux1 = Math.Min(cw0-1, ux1); uy1 = Math.Min(ch0-1, uy1);

    var frames = new List<int[,]>();
    foreach (var rc in rows) foreach (var cc in cols) {
      int cx0=cc[0]+ux0, cy0=rc[0]+uy0, cw=ux1-ux0+1, ch=uy1-uy0+1;
      // Flood the background IN from the cell edge, so an interior white
      // pixel (a snow drift's core) survives while the checkerboard goes.
      var bg = new bool[cw,ch];
      var seen = new bool[cw,ch];
      var st = new Stack<int>();
      for (int x=0;x<cw;x++){ st.Push(x); st.Push(0); st.Push(x); st.Push(ch-1); }
      for (int y=0;y<ch;y++){ st.Push(0); st.Push(y); st.Push(cw-1); st.Push(y); }
      while (st.Count > 0){
        int yy = st.Pop(); int xx = st.Pop();
        if (xx<0||yy<0||xx>=cw||yy>=ch) continue;
        if (seen[xx,yy]) continue;
        seen[xx,yy]=true;
        if (!IsBg(cx0+xx, cy0+yy)) continue;
        bg[xx,yy]=true;
        st.Push(xx+1); st.Push(yy); st.Push(xx-1); st.Push(yy);
        st.Push(xx); st.Push(yy+1); st.Push(xx); st.Push(yy-1);
      }

      var cell = new int[16,16];
      for (int ty=0;ty<16;ty++) for (int tx=0;tx<16;tx++){
        int x0 = (int)((long)tx*cw/16), x1 = (int)((long)(tx+1)*cw/16)-1;
        int y0 = (int)((long)ty*ch/16), y1 = (int)((long)(ty+1)*ch/16)-1;
        int tot=0, on=0; double sum=0;
        for (int y=y0;y<=y1;y++) for (int x=x0;x<=x1;x++){
          tot++;
          if (!bg[x,y]) { on++;
            sum += 0.299*R(cx0+x,cy0+y) + 0.587*G(cx0+x,cy0+y) + 0.114*B(cx0+x,cy0+y); }
        }
        // Thirty per cent rather than a majority: at sixteen pixels across,
        // a stroke one source-cell wide covers a third of the block under
        // it and a majority rule threw it away -- which is how a pair of
        // boots came back as two thin bars.
        cell[tx,ty] = (tot>0 && on*10 >= tot*3) ? (int)Math.Round(sum/on) : -1;
      }
      // Keep every cell: the grid is an equal division now, so an empty one
      // means the sheet had fewer drawings than the caller said it did, which
      // is worth seeing in the count rather than silently swallowing.
      bool any = false;
      for (int y=0;y<16 && !any;y++) for (int x=0;x<16;x++) if (cell[x,y]>=0) { any=true; break; }
      if (any) frames.Add(cell);
    }

    // Renormalise: the mod multiplies these by the colour it picks, so what
    // matters is the relative tone. Art drawn dark would come out invisible.
    int maxTone = 1;
    foreach (var f in frames) for (int y=0;y<16;y++) for (int x=0;x<16;x++)
      if (f[x,y] > maxTone) maxTone = f[x,y];

    int n2 = frames.Count, kept = 0;
    var dst = new Bitmap(16*n2, 16, PixelFormat.Format32bppArgb);
    for (int f=0; f<n2; f++)
      for (int y=0;y<16;y++) for (int x=0;x<16;x++){
        int t = frames[f][x,y];
        if (t < 0) dst.SetPixel(f*16+x, y, Color.FromArgb(0,0,0,0));
        else {
          int v = (int)Math.Min(255, Math.Round(t*255.0/maxTone));
          dst.SetPixel(f*16+x, y, Color.FromArgb(255,v,v,v));
          kept++;
        }
      }
    dst.Save(outPath, ImageFormat.Png);
    dst.Dispose();

    return string.Format(
      "source {0}x{1} alpha={2} | inner x{9}..{10} y{11}..{12} | grid {3}x{4} = {5} frames | brightest {6} | " +
      "wrote {7}x16, {8} opaque px",
      W, H, hasAlpha, cols.Count, rows.Count, n2, maxTone, 16*n2, kept, L, Rr, T, Bm);
  }
}
'@
}

$inFull = (Resolve-Path $In).Path
$outDir = Split-Path -Parent $Out
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$outFull = Join-Path (Resolve-Path $outDir).Path (Split-Path -Leaf $Out)
Write-Output ([SheetStrip]::Convert($inFull, $outFull, $Cols, $Rows, $BgLo, $BgHi))
