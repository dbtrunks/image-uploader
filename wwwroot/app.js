const MAX_FILES = 100;
const MAX_FILE_SIZE = 50 * 1024 * 1024;
const files = [];
let isUploading = false;
let noticeTimer;

const dropzone = document.querySelector("#dropzone");
const fileInput = document.querySelector("#file-input");
const queueSection = document.querySelector("#queue-section");
const fileList = document.querySelector("#file-list");
const uploadButton = document.querySelector("#upload-button");
const chooseFilesButton = document.querySelector("#choose-files");
const clearQueueButton = document.querySelector("#clear-queue");
const notice = document.querySelector("#notice");
const destinationSelect = document.querySelector("#destination-select");

chooseFilesButton.addEventListener("click", openFilePicker);
destinationSelect.addEventListener("change", renderQueue);
dropzone.addEventListener("click", event => {
  if (!event.target.closest("button")) openFilePicker();
});
fileInput.addEventListener("change", () => {
  clearUploadedFiles();
  addFiles(fileInput.files);
  fileInput.value = "";
});

for (const eventName of ["dragenter", "dragover"]) {
  dropzone.addEventListener(eventName, event => {
    event.preventDefault();
    dropzone.classList.add("drag-over");
  });
}
for (const eventName of ["dragleave", "drop"]) {
  dropzone.addEventListener(eventName, event => {
    event.preventDefault();
    dropzone.classList.remove("drag-over");
  });
}
dropzone.addEventListener("drop", event => addFiles(event.dataTransfer.files));

uploadButton.addEventListener("click", uploadPendingFiles);
clearQueueButton.addEventListener("click", () => {
  if (isUploading) return;
  files.splice(0, files.length);
  renderQueue();
});

loadDestinations();

function openFilePicker() {
  if (isUploading) return;
  clearUploadedFiles();
  fileInput.click();
}

function clearUploadedFiles() {
  const uploadedFiles = files.filter(item => item.status === "done").length;
  if (uploadedFiles > 0) {
    for (let index = files.length - 1; index >= 0; index--) {
      if (files[index].status === "done") files.splice(index, 1);
    }
    renderQueue();
  }
}

async function loadDestinations() {
  try {
    const response = await fetch("/api/destinations");
    if (!response.ok) throw new Error("Nie udało się pobrać miejsc docelowych.");
    const destinations = await response.json();
    destinationSelect.replaceChildren();

    if (destinations.length === 0) {
      destinationSelect.add(new Option("Brak skonfigurowanych miejsc", ""));
      showNotice("Administrator nie skonfigurował miejsc docelowych.");
      renderQueue();
      return;
    }

    //destinationSelect.add(new Option("Wybierz katalog…", ""));
    for (const destination of destinations) {
      destinationSelect.add(new Option(destination.name, destination.id));
    }
    destinationSelect.disabled = false;
  } catch (error) {
    destinationSelect.replaceChildren(new Option("Nie udało się wczytać katalogów", ""));
    showNotice(error.message || "Nie udało się wczytać katalogów.");
  }
  renderQueue();
}

function addFiles(selectedFiles) {
  if (isUploading) {
    showNotice("Poczekaj na zakończenie przesyłania.");
    return;
  }

  const incoming = Array.from(selectedFiles);
  const availableSlots = MAX_FILES - files.length;
  const accepted = incoming.slice(0, availableSlots);
  let rejected = incoming.length - accepted.length;

  for (const file of accepted) {
    if (file.size > MAX_FILE_SIZE) {
      rejected++;
      continue;
    }
    files.push({ file, status: "pending", progress: 0, error: "" });
  }

  if (rejected) showNotice(`${rejected} plików pominięto (limit kolejki lub 50 MB na plik).`);
  renderQueue();
}

function renderQueue() {
  queueSection.hidden = files.length === 0;
  fileList.replaceChildren();

  for (const [index, item] of files.entries()) {
    const row = document.createElement("li");
    row.className = "file-item";

    const preview = document.createElement("div");
    preview.className = "file-preview";
    if (item.file.type.startsWith("image/")) {
      const image = document.createElement("img");
      image.alt = "";
      image.src = URL.createObjectURL(item.file);
      image.addEventListener("load", () => URL.revokeObjectURL(image.src), { once: true });
      preview.append(image);
    } else {
      preview.innerHTML = '<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7 3.75h6.5L19 9.2v10.05a1 1 0 0 1-1 1H7a2 2 0 0 1-2-2v-13a1.5 1.5 0 0 1 2-1.5Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/><path d="M13 4v5h5m-9 4h6m-6 3h6" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
    }

    const info = document.createElement("div");
    info.className = "file-info";
    const name = document.createElement("p");
    name.className = "file-name";
    name.textContent = item.file.name;
    name.title = item.file.name;
    const meta = document.createElement("div");
    meta.className = "file-meta";
    meta.textContent = formatSize(item.file.size);
    info.append(name, meta);

    const progress = document.createElement("div");
    progress.className = "item-progress";
    progress.setAttribute("aria-label", `Postęp pliku ${item.file.name}`);
    const progressFill = document.createElement("div");
    progressFill.className = "item-progress-fill";
    progressFill.style.width = `${item.progress}%`;
    progress.append(progressFill);

    const status = document.createElement("span");
    status.className = `file-status${item.status === "done" ? " done" : item.status === "error" ? " error" : ""}`;
    status.textContent = item.status === "done" ? "Wysłano" :
      item.status === "uploading" ? `${Math.round(item.progress)}%` :
      item.status === "error" ? "Błąd" : "Oczekuje";
    if (item.error) status.title = item.error;

    const remove = document.createElement("button");
    remove.className = "remove-file";
    remove.type = "button";
    remove.textContent = "×";
    remove.setAttribute("aria-label", `Usuń plik ${item.file.name}`);
    remove.disabled = isUploading;
    remove.addEventListener("click", () => {
      if (isUploading) return;
      files.splice(index, 1);
      renderQueue();
    });

    row.append(preview, info, progress, status, remove);
    fileList.append(row);
  }

  updateProgress();
  uploadButton.disabled = isUploading || !destinationSelect.value || !files.some(item => item.status !== "done");
  uploadButton.querySelector("span").textContent = isUploading ? "Przesyłanie…" :
    files.some(item => item.status === "error") ? "Ponów nieudane pliki" : "Rozpocznij przesyłanie";
  clearQueueButton.disabled = isUploading;
  chooseFilesButton.disabled = isUploading || files.length >= MAX_FILES;
  destinationSelect.disabled = isUploading || files.some(item => item.status === "done") || destinationSelect.options.length < 2;
}

function updateProgress() {
  const sent = files.filter(item => item.status === "done").length;
  const remaining = files.length - sent;
  const active = files.find(item => item.status === "uploading");
  const progress = files.length ? Math.round((sent + (active ? active.progress / 100 : 0)) / files.length * 100) : 0;

  document.querySelector("#file-count").textContent = files.length;
  document.querySelector("#sent-count").textContent = sent;
  document.querySelector("#remaining-count").textContent = remaining;
  document.querySelector("#progress-percent").textContent = `${progress}%`;
  document.querySelector("#overall-progress-fill").style.width = `${progress}%`;
  document.querySelector("#progress-label").textContent = isUploading ? "Przesyłanie plików" :
    remaining === 0 && files.length ? "Wszystkie pliki zostały przesłane" :
    sent ? "Przesyłanie wstrzymane" : "Oczekiwanie na przesyłanie";
  document.querySelector("#queue-summary").textContent = isUploading ? "Nie zamykaj tej strony podczas przesyłania" :
    remaining === 0 && files.length ? "Gotowe — wszystkie pliki są na serwerze" : "Gotowe do przesłania";
}

async function uploadPendingFiles() {
  if (isUploading) return;
  isUploading = true;
  renderQueue();

  for (const item of files) {
    if (item.status === "done") continue;
    item.status = "uploading";
    item.progress = 0;
    item.error = "";
    renderQueue();

    try {
      await uploadFile(item, percent => {
        item.progress = percent;
        updateProgress();
        const row = fileList.children[files.indexOf(item)];
        if (row) {
          row.querySelector(".item-progress-fill").style.width = `${percent}%`;
          row.querySelector(".file-status").textContent = `${Math.round(percent)}%`;
        }
      });
      item.status = "done";
      item.progress = 100;
    } catch (error) {
      item.status = "error";
      item.error = error.message || "Nie udało się wysłać pliku.";
    }
    renderQueue();
  }

  isUploading = false;
  renderQueue();
  const failed = files.filter(item => item.status === "error").length;
  showNotice(failed ? `Wysłano pliki. Nie udało się przesłać ${failed}; możesz ponowić próbę.` : "Wszystkie pliki zostały przesłane.");
}

function uploadFile(item, onProgress) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open("POST", "/api/upload");
    request.upload.addEventListener("progress", event => {
      if (event.lengthComputable) onProgress(event.loaded / event.total * 100);
    });
    request.addEventListener("load", () => {
      if (request.status >= 200 && request.status < 300) resolve();
      else reject(new Error(request.responseText || "Serwer odrzucił plik."));
    });
    request.addEventListener("error", () => reject(new Error("Błąd połączenia z serwerem.")));
    request.addEventListener("abort", () => reject(new Error("Przesyłanie zostało przerwane.")));
    const data = new FormData();
    data.append("file", item.file, item.file.name);
    data.append("destinationId", destinationSelect.value);
    request.send(data);
  });
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function showNotice(message) {
  notice.textContent = message;
  notice.classList.add("visible");
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => notice.classList.remove("visible"), 4200);
}
